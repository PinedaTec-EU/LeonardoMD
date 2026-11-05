#!/usr/bin/env python3
"""Inspect bundled Mach-O load paths and apply one inside-out signing policy."""
from pathlib import Path
import argparse
import ctypes
import functools
import os
import re
import subprocess

MACHO_MAGIC = {b'\xfe\xed\xfa\xce', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xcf',
               b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca',
               b'\xca\xfe\xba\xbf', b'\xbf\xba\xfe\xca'}
LOAD_COMMANDS = {'LC_LOAD_DYLIB', 'LC_LOAD_WEAK_DYLIB', 'LC_REEXPORT_DYLIB',
                 'LC_LOAD_UPWARD_DYLIB', 'LC_LAZY_LOAD_DYLIB'}
# WebKit and other OS libraries can resolve through Apple's sealed OS Cryptex.
SYSTEM_ROOTS = ('/usr/lib/', '/System/Library/',
                '/System/Volumes/Preboot/Cryptexes/OS/usr/lib/',
                '/System/Volumes/Preboot/Cryptexes/OS/System/Library/')


def macho_files(bundle):
    files = []
    for path in sorted(bundle.rglob('*')):
        if path.is_symlink() or not path.is_file():
            continue
        with path.open('rb') as stream:
            if stream.read(4) in MACHO_MAGIC:
                files.append(path)
    return files


def signing_components(bundle):
    components = set(macho_files(bundle))
    components.update(path for path in bundle.rglob('*')
                      if not path.is_symlink() and path.is_dir()
                      and path.suffix in {'.framework', '.app', '.xpc'})
    return sorted(components, key=lambda path: (-len(path.parts), str(path)))


def sign_bundle(bundle, identity):
    # Keep vendor entitlements; sign code before its enclosing resource seals.
    for component in [*signing_components(bundle), bundle]:
        subprocess.run(['/usr/bin/codesign', '--force', '--options', 'runtime', '--timestamp',
                        '--preserve-metadata=entitlements', '--sign', identity, str(component)], check=True)


def signing_team(path):
    result = subprocess.run(['/usr/bin/codesign', '-d', '--verbose=2', str(path)],
                            check=True, capture_output=True, text=True)
    match = re.search(r'^TeamIdentifier=(.+)$', result.stderr, re.MULTILINE)
    return match.group(1) if match and match.group(1) != 'not set' else None


def inspect_signing(bundle):
    subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(bundle)], check=True)
    team = signing_team(bundle)
    if team:
        for component in signing_components(bundle):
            if signing_team(component) != team:
                raise ValueError(f'Embedded signing team differs from app: {component.relative_to(bundle)}; '
                                 're-sign the entire QA copy inside out with --sign-identity')


def load_commands(image, architecture):
    output = subprocess.check_output(['/usr/bin/otool', '-arch', architecture, '-l', str(image)], text=True)
    command, paths, dependencies = None, [], []
    for line in output.splitlines():
        fields = line.strip().split()
        if fields[:1] == ['cmd']:
            command = fields[1]
        elif fields[:1] == ['path'] and command == 'LC_RPATH':
            paths.append(line.strip()[5:].rsplit(' (offset ', 1)[0])
        elif fields[:1] == ['name'] and command in LOAD_COMMANDS:
            dependencies.append((line.strip()[5:].rsplit(' (offset ', 1)[0],
                                 command == 'LC_LOAD_WEAK_DYLIB'))
    return paths, dependencies


def expand_path(value, image, executable):
    for token, directory in (('@loader_path', image.parent), ('@executable_path', executable.parent)):
        if value == token or value.startswith(token + '/'):
            return str(directory) + value[len(token):]
    return value


def system_path(name):
    return (Path(name).is_absolute() and os.path.normpath(name).startswith(SYSTEM_ROOTS)
            and str(Path(name).resolve()).startswith(SYSTEM_ROOTS))


@functools.cache
def shared_cache_lookup():
    lookup = ctypes.CDLL('/usr/lib/system/libdyld.dylib')._dyld_shared_cache_contains_path
    lookup.argtypes = [ctypes.c_char_p]
    lookup.restype = ctypes.c_bool
    return lookup


def image_types(image):
    header = subprocess.check_output(['/usr/bin/otool', '-hv', str(image)], text=True)
    rows = [line.split() for line in header.splitlines()]
    return {row[4] for row in rows if len(row) > 4
            and row[0] in {'MH_MAGIC', 'MH_MAGIC_64', 'MH_CIGAM', 'MH_CIGAM_64'}}


def executable_image(image):
    types = image_types(image)
    if 'EXECUTE' in types and len(types) > 1:
        raise ValueError(f'Mixed executable/library image types: {image}')
    return types == {'EXECUTE'}


def system_image_available(name):
    if shared_cache_lookup()(os.fsencode(name)):
        return True
    path = Path(name)
    if not path.is_file():
        return False
    with path.open('rb') as stream:
        if stream.read(4) not in MACHO_MAGIC:
            raise ValueError(f'System dependency is not a Mach-O library: {name}')
    if image_types(path) != {'DYLIB'}:
        raise ValueError(f'System dependency is not a dynamic library: {name}')
    return True


def image_architectures(image):
    architectures = subprocess.check_output(['/usr/bin/lipo', '-archs', str(image)], text=True).split()
    if not architectures:
        raise ValueError(f'Cannot determine image architectures: {image}')
    return architectures


def resolve_dependency(name, image, executable, runpaths, bundle, *, weak=False):
    candidates = ([str(Path(path) / name[len('@rpath/'):]) for path in runpaths]
                  if name.startswith('@rpath/') else [expand_path(name, image, executable)])
    for candidate in candidates:
        path = Path(candidate)
        if not path.is_absolute():
            raise ValueError(f'Unresolved bundled dependency {name}: relative or unsupported '
                             f'runpath cannot be validated: {candidate}')
        if system_path(candidate) and system_image_available(candidate):
            return None
        if path.is_file():
            if not path.resolve().is_relative_to(bundle):
                raise ValueError(f'Unresolved bundled dependency {name}: first existing candidate '
                                 f'escapes the bundle: {candidate}')
            if image_types(path) != {'DYLIB'}:
                raise ValueError(f'Bundled dependency is not a dynamic library: {candidate}')
            return path.resolve()
    if weak:
        return None  # Weak-linked images are permitted to be absent at runtime.
    raise ValueError(f'Unresolved bundled dependency {name} from {image.relative_to(bundle)}; '
                     f'searched: {", ".join(candidates)}')


def inspect_dependencies(bundle, executable):
    bundle, executable = bundle.resolve(), executable.resolve()
    if not executable.is_relative_to(bundle):
        raise ValueError('App executable resolves outside its bundle')
    inspected = set()
    architecture_cache = {}

    def architectures(image):
        if image not in architecture_cache:
            architecture_cache[image] = image_architectures(image)
        return architecture_cache[image]

    def visit(image, launcher, architecture, inherited):
        key = (launcher, architecture, image, tuple(inherited))
        if key in inspected:
            return
        inspected.add(key)
        if architecture not in architectures(image):
            raise ValueError(f'Missing architecture {architecture} in bundled dependency: {image}')
        paths, names = load_commands(image, architecture)
        runpaths = list(dict.fromkeys([*(expand_path(p, image, launcher) for p in paths), *inherited]))
        for name, weak in names:
            dependency = resolve_dependency(name, image, launcher, runpaths, bundle, weak=weak)
            if dependency is not None and dependency != image:
                visit(dependency, launcher, architecture, runpaths)

    launchers = []
    for image in macho_files(bundle):
        if executable_image(image):
            launchers.append(image.resolve())
    if executable not in launchers:
        raise ValueError('The main application binary must be a Mach-O executable')
    for launcher in dict.fromkeys([executable, *launchers]):
        for architecture in architectures(launcher):
            visit(launcher, launcher, architecture, [])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle', type=Path)
    parser.add_argument('--sign-identity', required=True)
    args = parser.parse_args()
    sign_bundle(args.bundle, args.sign_identity)
    inspect_signing(args.bundle)

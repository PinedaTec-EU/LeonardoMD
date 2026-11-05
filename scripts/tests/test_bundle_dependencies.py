"""Regression coverage for the prelaunch gate, including real otool inspection."""
import importlib.util
from pathlib import Path
import plistlib
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).parents[1]
SPEC = importlib.util.spec_from_file_location('bundle_dependencies', SCRIPTS / 'bundle-dependencies.py')
deps = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(deps)


def macho(path, dependencies=(), rpaths=(), filetype=2, load_command=12):
    """Minimal arm64 Mach-O fixture: parsed by real otool, never executed."""
    commands = []
    for name in rpaths:
        value = name.encode() + b'\0'
        size = (12 + len(value) + 7) // 8 * 8
        commands.append(struct.pack('<III', 0x8000001c, size, 12) + value + bytes(size - 12 - len(value)))
    for name in dependencies:
        value = name.encode() + b'\0'
        size = (24 + len(value) + 7) // 8 * 8
        commands.append(struct.pack('<IIIIII', load_command, size, 24, 0, 0, 0) + value + bytes(size - 24 - len(value)))
    data = b''.join(commands)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(struct.pack('<IIIIIIII', 0xfeedfacf, 0x100000c, 0, filetype, len(commands), len(data), 0, 0) + data)


class DependencyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='qa dependencies ')
        self.addCleanup(self.temp.cleanup)
        self.bundle = Path(self.temp.name) / 'App.app'
        self.executable = self.bundle / 'Contents/MacOS/LeonardoMD'
        self.sparkle = self.bundle / 'Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle'
        self.name = '@rpath/Sparkle.framework/Versions/B/Sparkle'
        macho(self.executable, [self.name, '/usr/lib/libSystem.B.dylib'],
              ['/usr/lib/swift', '@executable_path/../Frameworks'])
        macho(self.sparkle, ['/usr/lib/libSystem.B.dylib'], filetype=6)

    def test_real_otool_resolves_framework_under_bundle_with_spaces(self):
        deps.inspect_dependencies(self.bundle, self.executable)

    def test_missing_framework_rejected_even_with_system_swift_rpath(self):
        self.sparkle.unlink()
        with self.assertRaisesRegex(ValueError, 'Unresolved bundled dependency.*Sparkle'):
            deps.inspect_dependencies(self.bundle, self.executable)

    def test_framework_exists_but_runpath_is_wrong(self):
        macho(self.executable, [self.name], ['@loader_path'])
        with self.assertRaisesRegex(ValueError, 'Unresolved bundled dependency'):
            deps.inspect_dependencies(self.bundle, self.executable)

    def test_existing_external_rpath_cannot_be_hidden_by_a_bundled_fallback(self):
        outside = Path(self.temp.name) / 'external'
        library = outside / 'Sparkle.framework/Versions/B/Sparkle'
        macho(library, ['/usr/lib/libSystem.B.dylib'], filetype=6)
        macho(self.executable, [self.name], [str(outside), '@executable_path/../Frameworks'])
        with self.assertRaisesRegex(ValueError, 'first existing candidate escapes'):
            deps.inspect_dependencies(self.bundle, self.executable)

    def test_earlier_rpath_symlink_escape_cannot_be_hidden_by_a_fallback(self):
        outside = Path(self.temp.name) / 'external.dylib'
        macho(outside, ['/usr/lib/libSystem.B.dylib'], filetype=6)
        alias = self.bundle / 'Contents/MacOS/shim/Sparkle.framework/Versions/B/Sparkle'
        alias.parent.mkdir(parents=True)
        alias.symlink_to(outside)
        macho(self.executable, [self.name], ['@executable_path/shim', '@executable_path/../Frameworks'])
        with self.assertRaisesRegex(ValueError, 'first existing candidate escapes'):
            deps.inspect_dependencies(self.bundle, self.executable)

    def test_nonexistent_external_rpath_allows_a_bundled_fallback(self):
        macho(self.executable, [self.name], [str(Path(self.temp.name) / 'absent'),
                                             '@executable_path/../Frameworks'])
        deps.inspect_dependencies(self.bundle, self.executable)

    def test_relative_rpath_cannot_be_silently_skipped_for_a_fallback(self):
        macho(self.executable, [self.name], ['relative-first', '@executable_path/../Frameworks'])
        with self.assertRaisesRegex(ValueError, 'relative or unsupported runpath'):
            deps.inspect_dependencies(self.bundle, self.executable)

    def test_system_shared_cache_candidate_is_recognized_before_a_fallback(self):
        macho(self.executable, ['@rpath/libswiftCore.dylib'], ['/usr/lib/swift', '@loader_path/absent'])
        deps.inspect_dependencies(self.bundle, self.executable)

    def test_framework_symlink_escaping_bundle_is_rejected(self):
        outside = Path(self.temp.name) / 'outside'
        self.sparkle.rename(outside)
        self.sparkle.symlink_to(outside)
        with self.assertRaisesRegex(ValueError, 'Unresolved bundled dependency'):
            deps.inspect_dependencies(self.bundle, self.executable)

    def test_transitive_dependency_and_loader_path(self):
        child = self.sparkle.parent / 'child.dylib'
        macho(self.sparkle, ['@loader_path/child.dylib'], filetype=6)
        macho(child, ['/usr/lib/libSystem.B.dylib'], filetype=6)
        deps.inspect_dependencies(self.bundle, self.executable)
        child.unlink()
        with self.assertRaisesRegex(ValueError, 'child.dylib'):
            deps.inspect_dependencies(self.bundle, self.executable)

    def test_absolute_development_dependency_is_not_a_portable_bundle(self):
        outside = Path(self.temp.name) / 'outside.dylib'
        macho(outside)
        macho(self.executable, [str(outside)])
        with self.assertRaisesRegex(ValueError, 'Unresolved bundled dependency'):
            deps.inspect_dependencies(self.bundle, self.executable)

    def test_system_prefix_cannot_hide_absolute_traversal(self):
        outside = Path(self.temp.name) / 'outside.dylib'
        macho(outside)
        for root in ('/usr/lib/', '/System/Library/'):
            with self.subTest(root=root):
                macho(self.executable, [root + '../../' + str(outside).lstrip('/')])
                with self.assertRaisesRegex(ValueError, 'Unresolved bundled dependency'):
                    deps.inspect_dependencies(self.bundle, self.executable)

    def test_system_prefix_cannot_hide_a_symlink_escape(self):
        approved = Path(self.temp.name) / 'system'
        approved.mkdir()
        outside = Path(self.temp.name) / 'outside.dylib'
        macho(outside)
        alias = approved / 'alias.dylib'
        alias.symlink_to(outside)
        macho(self.executable, [str(alias)])
        with patch.object(deps, 'SYSTEM_ROOTS', (str(approved) + '/',)):
            with self.assertRaisesRegex(ValueError, 'Unresolved bundled dependency'):
                deps.inspect_dependencies(self.bundle, self.executable)

    def test_system_paths_can_normalize_inside_the_approved_root(self):
        macho(self.executable, ['/usr/lib/../lib/libSystem.B.dylib'])
        deps.inspect_dependencies(self.bundle, self.executable)

    def test_lazy_loaded_and_transitive_dependencies_are_inspected(self):
        macho(self.executable, [self.name], ['@executable_path/../Frameworks'], load_command=0x20)
        child = self.sparkle.parent / 'lazy-child.dylib'
        macho(self.sparkle, ['@loader_path/lazy-child.dylib'], filetype=6, load_command=0x20)
        macho(child, ['/usr/lib/libSystem.B.dylib'], filetype=6)
        deps.inspect_dependencies(self.bundle, self.executable)
        child.unlink()
        with self.assertRaisesRegex(ValueError, 'lazy-child.dylib'):
            deps.inspect_dependencies(self.bundle, self.executable)
        self.sparkle.unlink()
        with self.assertRaisesRegex(ValueError, 'Sparkle'):
            deps.inspect_dependencies(self.bundle, self.executable)

    def test_standalone_helper_missing_dependency_is_rejected(self):
        helper = self.bundle / 'Contents/MacOS/Helper'
        macho(helper, ['@loader_path/missing.dylib'])
        with self.assertRaisesRegex(ValueError, 'missing.dylib'):
            deps.inspect_dependencies(self.bundle, self.executable)

    def test_xpc_graph_uses_its_own_executable_context(self):
        helper = self.bundle / 'Contents/XPCServices/Helper.xpc/Contents/MacOS/Helper'
        library = helper.parent.parent / 'Frameworks/Private.dylib'
        macho(helper, ['@executable_path/../Frameworks/Private.dylib'])
        macho(library, ['/usr/lib/libSystem.B.dylib'], filetype=6)
        deps.inspect_dependencies(self.bundle, self.executable)
        library.unlink()
        with self.assertRaisesRegex(ValueError, 'Private.dylib'):
            deps.inspect_dependencies(self.bundle, self.executable)

    def test_shared_library_is_rechecked_under_each_launcher_context(self):
        common = self.bundle / 'Contents/Frameworks/Common.dylib'
        macho(self.executable, ['@rpath/Common.dylib'], ['@executable_path/../Frameworks'])
        macho(common, ['@executable_path/local.dylib'], filetype=6)
        macho(self.executable.parent / 'local.dylib', filetype=6)
        helper = self.bundle / 'Contents/XPCServices/Helper.xpc/Contents/MacOS/Helper'
        macho(helper, ['@rpath/Common.dylib'], ['@executable_path/../../../../Frameworks'])
        with self.assertRaisesRegex(ValueError, 'local.dylib'):
            deps.inspect_dependencies(self.bundle, self.executable)
        macho(helper.parent / 'local.dylib', filetype=6)
        deps.inspect_dependencies(self.bundle, self.executable)

    def test_main_binary_must_have_executable_macho_type(self):
        macho(self.executable, filetype=6)
        with self.assertRaisesRegex(ValueError, 'Mach-O executable'):
            deps.inspect_dependencies(self.bundle, self.executable)

    def test_executable_type_is_not_inferred_from_a_filename(self):
        impostor = self.bundle / 'Contents/MacOS/EXECUTE/LeonardoMD'
        macho(impostor, filetype=6)
        with self.assertRaisesRegex(ValueError, 'Mach-O executable'):
            deps.inspect_dependencies(self.bundle, impostor)

    def test_cli_rejects_missing_dependency_before_signing_or_launch(self):
        self.sparkle.unlink()
        (self.bundle / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable': 'LeonardoMD'}))
        result = subprocess.run(['python3', str(SCRIPTS / 'qa-bundle.py'), '--verify-only', str(self.bundle)],
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Unresolved bundled dependency', result.stderr)

    def test_team_mismatch_is_rejected_even_when_deep_verification_passes(self):
        for nested_team in (None, 'VENDOR'):
            with self.subTest(team=nested_team), patch.object(deps.subprocess, 'run'), \
                    patch.object(deps, 'signing_team', side_effect=lambda p: 'OWNER' if p == self.bundle else nested_team):
                with self.assertRaisesRegex(ValueError, 'signing team differs'):
                    deps.inspect_signing(self.bundle)

    def test_same_team_and_adhoc_development_are_supported(self):
        for team in ('OWNER', None):
            with self.subTest(team=team), patch.object(deps.subprocess, 'run') as run, \
                    patch.object(deps, 'signing_team', return_value=team):
                deps.inspect_signing(self.bundle)
                self.assertIn('--deep', run.call_args.args[0])

    def test_signing_is_inside_out_includes_standalone_code_and_preserves_entitlements(self):
        updater = self.sparkle.parent / 'Autoupdate'
        macho(updater)
        with patch.object(deps.subprocess, 'run') as run:
            deps.sign_bundle(self.bundle, 'Developer ID')
        paths = [Path(call.args[0][-1]) for call in run.call_args_list]
        framework = self.bundle / 'Contents/Frameworks/Sparkle.framework'
        self.assertLess(paths.index(self.sparkle), paths.index(framework))
        self.assertLess(paths.index(updater), paths.index(framework))
        self.assertEqual(paths[-1], self.bundle)
        for call in run.call_args_list:
            self.assertIn('--preserve-metadata=entitlements', call.args[0])
            self.assertIn('runtime', call.args[0])


if __name__ == '__main__':
    unittest.main()

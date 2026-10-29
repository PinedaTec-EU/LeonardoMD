"""Canonical PR evidence declarations and compilation-ledger comparison."""
import argparse
import json
from pathlib import Path
import re
import subprocess

HEADING = '## Implementation-owned visual evidence'
HEAD = re.compile(r'^Reviewed candidate: `([0-9a-f]{40})`\.$', re.MULTILINE)
COUNT = re.compile(r'^Compilation build delta: `(0|[1-9][0-9]*)`\.$', re.MULTILINE)
COUNT_MENTION = re.compile(r'build[\s-]+delta', re.IGNORECASE)


def build_count(entry):
    if entry is None:
        return 0
    if not isinstance(entry, dict):
        raise ValueError('Ledger entry must be an object')
    value = entry.get('build', 0)
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        raise ValueError('Ledger build count must be a nonnegative integer')
    return value


def declaration(head, entry):
    if not re.fullmatch(r'[0-9a-f]{40}', head):
        raise ValueError('Evidence requires a full immutable head SHA')
    return f'{HEADING}\n\nReviewed candidate: `{head}`.\nCompilation build delta: `{build_count(entry)}`.\n'


def validate(snapshot):
    head, author = snapshot['head'], snapshot['author']
    declaration(head, snapshot['entry'])  # Validate the snapshot even without comments.
    expected = build_count(snapshot['entry'])
    matched = 0
    failures = []
    for comment in snapshot['comments']:
        body = comment['body'] or ''
        if comment['user']['login'] != author or HEADING not in body.splitlines():
            continue
        heads = HEAD.findall(body)
        label = f"Evidence comment {comment['id']}"
        if len(heads) != 1:
            failures.append(f'{label}: requires one canonical Reviewed candidate SHA')
            continue
        if heads[0] != head:
            continue  # Historical evidence belongs to its original immutable head.
        matched += 1
        counts = COUNT.findall(body)
        mentions = COUNT_MENTION.findall(body)
        if len(counts) != 1 or len(mentions) != 1:
            failures.append(f'{label}: requires one canonical numeric Compilation build delta line; remove duplicate prose counts')
        elif int(counts[0]) != expected:
            failures.append(f'{label}: evidence count {counts[0]} differs from ledger count {expected}')
    if failures:
        raise ValueError('\n'.join(failures))
    return f'Validated {matched} current-head author evidence comment(s); ledger build delta {expected}. No evidence is required by this count-only check.'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    check = commands.add_parser('check')
    check.add_argument('snapshot', type=Path)
    emit = commands.add_parser('emit')
    emit.add_argument('--pr-number', type=int, required=True)
    emit.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    try:
        if args.command == 'check':
            print(validate(json.loads(args.snapshot.read_text(encoding='utf-8'))))
        else:
            if args.pr_number <= 0:
                raise ValueError('PR number must be positive')
            head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=args.root, text=True).strip()
            path = f'deploy/version/entries/{args.pr_number}.yaml'
            tracked = subprocess.check_output(['git', 'ls-tree', 'HEAD', '--', path], cwd=args.root, text=True)
            data = json.loads(subprocess.check_output(['git', 'show', f'HEAD:{path}'], cwd=args.root, text=True)) if tracked else None
            print(declaration(head, data), end='')
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'evidence-compilation: {error}\n')


if __name__ == '__main__':
    main()

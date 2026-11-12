"""Run the real evidence CLI against temporary, immutable Git/JSON fixtures."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'scripts/evidence_compilation.py'
WORKFLOW = ROOT / '.github/workflows/evidence-compilation.yml'
HEAD = 'a' * 40
HEADING = '## Implementation-owned visual evidence'


def evidence(head=HEAD, count='9', suffix=''):
    return f'{HEADING}\n\nReviewed candidate: `{head}`.\nCompilation build delta: `{count}`.\n{suffix}'


class EvidenceCompilationTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)

    def check(self, comments, entry=None):
        snapshot = self.root / 'snapshot.json'
        snapshot.write_text(json.dumps({'head': HEAD, 'author': 'owner',
            'entry': {'summary': 'Example', 'build': 9} if entry is None else entry,
            'comments': [{'id': index + 1, 'user': {'login': user}, 'body': body}
                         for index, (user, body) in enumerate(comments)]}))
        original = snapshot.read_bytes()
        result = subprocess.run([sys.executable, str(SCRIPT), 'check', str(snapshot)],
                                text=True, capture_output=True)
        self.assertEqual(snapshot.read_bytes(), original)
        return result

    def test_current_head_matches(self):
        result = self.check([('owner', evidence())])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Validated 1 current-head', result.stdout)

    def test_mismatch_fails(self):
        result = self.check([('owner', evidence(count='7'))])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('evidence count 7 differs from ledger count 9', result.stderr)

    def test_missing_malformed_duplicate_or_prose_counts_fail(self):
        variants = [evidence().replace('Compilation build delta: `9`.\n', ''),
                    evidence(count='nine'), evidence(count='-1'), evidence(count='true'),
                    evidence(count='09'), evidence(suffix='Compilation build delta: `9`.'),
                    evidence(suffix='The build delta remains seven.'),
                    evidence(suffix='Build-delta: 7')]
        for body in variants:
            with self.subTest(body=body):
                self.assertNotEqual(self.check([('owner', body)]).returncode, 0)

    def test_historical_and_non_author_counts_do_not_substitute(self):
        result = self.check([('owner', evidence(head='b' * 40, count='1')),
                             ('reviewer', evidence(count='1'))])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Validated 0 current-head', result.stdout)
        self.assertIn('No evidence is required', result.stdout)
        self.assertNotEqual(self.check([('owner', evidence()), ('owner', evidence(count='7'))]).returncode, 0)

    def test_malformed_or_duplicate_candidate_fails(self):
        for body in [evidence(head='short'), evidence(suffix=f'Reviewed candidate: `{HEAD}`.')]:
            self.assertNotEqual(self.check([('owner', body)]).returncode, 0)

    def test_invalid_ledger_fails_even_without_evidence(self):
        for entry in [[], {'build': True}, {'build': -1}, {'build': '9'}]:
            self.assertNotEqual(self.check([], entry=entry).returncode, 0)

    def test_no_compilation_means_zero_without_allocating_a_build(self):
        result = self.check([('owner', evidence(count='0'))], entry={'summary': 'Governance'})
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_ordinary_comments_are_untouched(self):
        result = self.check([('owner', 'Some review prose'), ('reviewer', None)])
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_emit_reads_committed_head_not_dirty_or_unrelated_entries(self):
        def git(*args):
            return subprocess.check_output(['git', *args], cwd=self.root, text=True).strip()
        git('init', '-q')
        git('config', 'user.name', 'Fixture')
        git('config', 'user.email', 'fixture@example.invalid')
        entries = self.root / 'deploy/version/entries'
        entries.mkdir(parents=True)
        entry = entries / '42.yaml'
        entry.write_text('{"build":9}')
        other = entries / '43.yaml'
        other.write_text('{"build":15}')
        git('add', '.')
        git('commit', '-qm', 'Fixture')
        head = git('rev-parse', 'HEAD')
        entry.write_text('{"build":10}')
        result = subprocess.run([sys.executable, str(SCRIPT), 'emit', '--pr-number', '42',
                                 '--root', str(self.root)], text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, f'## Implementation-owned validation evidence\n\nReviewed candidate: `{head}`.\nCompilation build delta: `9`.\n')
        self.assertEqual(entry.read_text(), '{"build":10}')
        self.assertEqual(other.read_text(), '{"build":15}')

    def test_workflow_trust_event_and_failure_contract(self):
        workflow = WORKFLOW.read_text()
        for required in ['pull_request_target:', 'issue_comment:', 'created, edited, deleted',
                         'synchronize', 'workflow_dispatch:', 'checks: write',
                         'ref: ${{ github.event.repository.default_branch }}',
                         'persist-credentials: false', 'github.paginate', 'ref: pr.head.sha',
                         'if (error.status !== 404) throw error',
                         "process.env.SNAPSHOT_OUTCOME === 'success' && process.env.COMPARE_OUTCOME === 'success'",
                         "head_sha: process.env.REVIEWED_HEAD", "if (!passed) core.setFailed"]:
            self.assertIn(required, workflow)
        for prohibited in ['secrets.', 'ref: ${{ github.event.pull_request.head', 'eval(', 'exec(', 'checkout@v4\n        with:\n          ref: ${{ github.head_ref']:
            self.assertNotIn(prohibited, workflow)


if __name__ == '__main__':
    unittest.main()

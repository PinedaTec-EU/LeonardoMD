"""Exercise the actual workflow JavaScript with mocked GitHub transport."""
import json
from pathlib import Path
import shutil
import subprocess
import textwrap
import unittest

WORKFLOW = Path(__file__).resolve().parents[2] / '.github/workflows/evidence-compilation.yml'


@unittest.skipUnless(shutil.which('node'), 'Node.js is required for workflow JavaScript tests')
class EvidenceWorkflowTests(unittest.TestCase):
    def run_script(self, index, *, error=None, compare='success', snapshot='success'):
        scripts = WORKFLOW.read_text().split('          script: |\n')[1:]
        source = textwrap.dedent(scripts[index].split('\n      - name:', 1)[0])
        harness = """
        const output = {}, calls = [], files = {};
        const core = {setOutput: (key, value) => output[key] = value, setFailed: value => output.failure = value};
        const pr = {state:'open', base:{ref:'main'}, head:{sha:'a'.repeat(40), repo:{full_name:'owner/repo'}}, user:{login:'owner'}};
        const context = {repo:{owner:'owner',repo:'repo'}, serverUrl:'https://github.com',runId:123,
          payload:{repository:{full_name:'owner/repo'},issue:{number:42}}};
        const github = {rest:{pulls:{get:async () => ({data:pr})}, repos:{getContent:async request => {
          calls.push(request);
          if (ERROR !== null) { const error = new Error('API failure'); error.status = ERROR; throw error; }
          return {data:{encoding:'base64',type:'file',content:Buffer.from('{"build":9}').toString('base64')}};
        }}, issues:{listComments:()=>{}}, checks:{create:async request => calls.push(request)}},
          paginate:async () => [{id:1,user:{login:'owner'},body:'evidence'}]};
        const require = name => {if(name !== 'fs') throw new Error('Unexpected module');
          return {writeFileSync:(path,value)=>files[path]=JSON.parse(value)};};
        (async () => {
          try { SOURCE } catch(error) { output.error = error.message; }
          process.stdout.write(JSON.stringify({output,calls,files}));
        })();
        """.replace('ERROR', json.dumps(error)).replace('SOURCE', source)
        result = subprocess.run(['node', '-e', harness], text=True, capture_output=True,
            env={'PATH': str(Path(shutil.which('node')).parent), 'REVIEWED_HEAD': 'a' * 40,
                 'SNAPSHOT_OUTCOME': snapshot, 'COMPARE_OUTCOME': compare})
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_snapshot_reads_exact_sha_and_comments_as_data(self):
        result = self.run_script(0)
        self.assertEqual(result['calls'][0]['ref'], 'a' * 40)
        self.assertEqual(result['calls'][0]['path'], 'deploy/version/entries/42.yaml')
        snapshot = result['files']['/tmp/evidence-snapshot.json']
        self.assertEqual(snapshot['head'], 'a' * 40)
        self.assertEqual(snapshot['entry'], {'build': 9})
        self.assertEqual(snapshot['author'], 'owner')
        self.assertEqual(len(snapshot['comments']), 1)

    def test_only_missing_entry_is_tolerated(self):
        result = self.run_script(0, error=404)
        self.assertIsNone(result['files']['/tmp/evidence-snapshot.json']['entry'])
        for status in [403, 429, 500]:
            with self.subTest(status=status):
                result = self.run_script(0, error=status)
                self.assertEqual(result['output']['error'], 'API failure')
                self.assertEqual(result['files'], {})

    def test_check_success_requires_both_steps_and_binds_sha(self):
        for snapshot, compare in [('success', 'success'), ('failure', 'skipped'), ('success', 'failure')]:
            result = self.run_script(1, snapshot=snapshot, compare=compare)
            check = result['calls'][0]
            passed = snapshot == compare == 'success'
            self.assertEqual(check['head_sha'], 'a' * 40)
            self.assertEqual(check['conclusion'], 'success' if passed else 'failure')
            self.assertEqual('failure' in result['output'], not passed)

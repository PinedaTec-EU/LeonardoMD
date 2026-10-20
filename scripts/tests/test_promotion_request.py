import contextlib
import io
import json
import os
from pathlib import Path
import textwrap
import unittest
from unittest.mock import MagicMock, patch
import urllib.error

WORKFLOW = Path(__file__).resolve().parents[2] / '.github/workflows/promote-beta.yml'


class PromotionRequestTests(unittest.TestCase):
    def setUp(self):
        source = WORKFLOW.read_text().split("python3 -I - <<'PYTHON'\n", 1)[1].split('          PYTHON', 1)[0]
        self.script = compile(textwrap.dedent(source), str(WORKFLOW), 'exec')
        self.environment = {'BETA_TAG': 'v0.1.15', 'SOURCE_SHA': 'a' * 40,
            'ACCEPTANCE_URL': 'https://github.com/PinedaTec-EU/LeonardoMD/issues/236#issuecomment-99',
            'REQUEST_ID': 'stable-0.1.15', 'DISPATCH_TOKEN': 'synthetic-sensitive-token'}

    def invoke(self, *, error=None):
        response = MagicMock()
        response.__enter__.return_value.status = 204
        output = io.StringIO()
        with patch.dict(os.environ, self.environment), patch('urllib.request.urlopen', return_value=response,
                side_effect=error) as send, contextlib.redirect_stdout(output):
            failure = None
            try:
                exec(self.script, {})
            except SystemExit as exception:
                failure = str(exception)
        return send, output.getvalue(), failure

    def test_dispatch_binds_exact_intermediate_beta_without_bump_or_latest_selection(self):
        send, output, failure = self.invoke()
        self.assertIsNone(failure)
        request = send.call_args.args[0]
        self.assertEqual('https://api.github.com/repos/PinedaTec-EU/pinedatec-ci/dispatches', request.full_url)
        payload = json.loads(request.data)
        self.assertEqual('promote-release-candidate', payload['event_type'])
        self.assertEqual({'schema_version': 1, 'repository': 'PinedaTec-EU/LeonardoMD',
            'version': '0.1.15', 'beta_tag': 'v0.1.15', 'source_sha': 'a' * 40,
            'acceptance_url': self.environment['ACCEPTANCE_URL'], 'request_id': 'stable-0.1.15'}, payload['client_payload'])
        self.assertIn('pending', output)
        self.assertNotIn(self.environment['DISPATCH_TOKEN'], output)

    def test_invalid_or_mutable_inputs_never_dispatch(self):
        for name, value in [('BETA_TAG', 'latest'), ('BETA_TAG', 'v0.1.15-beta'), ('SOURCE_SHA', 'main'),
                            ('ACCEPTANCE_URL', 'https://example.com/acceptance'), ('REQUEST_ID', 'bad\ninput'),
                            ('DISPATCH_TOKEN', '')]:
            self.setUp()
            self.environment[name] = value
            with self.subTest(field=name, value=value):
                send, _, failure = self.invoke()
                self.assertIsNotNone(failure)
                send.assert_not_called()

    def test_request_failure_does_not_leak_token_or_claim_publication(self):
        error = urllib.error.HTTPError('https://api.github.com', 403, self.environment['DISPATCH_TOKEN'], {}, None)
        _, output, failure = self.invoke(error=error)
        self.assertEqual('Dispatch failed with HTTP 403.', failure)
        self.assertNotIn(self.environment['DISPATCH_TOKEN'], output + failure)
        self.assertNotIn('succeeds', output)

    def test_credentialed_adapter_uses_no_checkout_build_or_publication_key(self):
        workflow = WORKFLOW.read_text()
        for forbidden in ('actions/checkout', 'swift build', 'swift test', 'private-key:', 'contents: write'):
            self.assertNotIn(forbidden, workflow)
        self.assertIn("github.ref == 'refs/heads/main'", workflow)


if __name__ == '__main__':
    unittest.main()

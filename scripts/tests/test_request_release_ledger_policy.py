import contextlib
import copy
import io
import json
import os
from pathlib import Path
import tempfile
import textwrap
import unittest
from unittest.mock import patch, MagicMock
import urllib.error


WORKFLOW = Path(__file__).resolve().parents[2] / '.github/workflows/release-ledger-policy.yml'
REPOSITORY = 'PinedaTec-EU/LeonardoMD'


class RequestPolicyTests(unittest.TestCase):
    def setUp(self):
        workflow = WORKFLOW.read_text()
        self.script = compile(textwrap.dedent(workflow.split("python3 -I - <<'PYTHON'\n", 1)[1]
                                             .split('          PYTHON', 1)[0]), str(WORKFLOW), 'exec')
        self.event = {'action': 'ready_for_review', 'pull_request': {
            'number': 65, 'draft': False, 'state': 'open',
            'head': {'repo': {'full_name': REPOSITORY}},
            'base': {'ref': 'main', 'repo': {'full_name': REPOSITORY}}}}

    def run_event(self, event, token='fake-dispatch-token', error=None):
        with tempfile.TemporaryDirectory() as directory:
            event_path = Path(directory) / 'event.json'
            event_path.write_text(json.dumps(event))
            response = MagicMock()
            response.__enter__.return_value.status = 204
            output = io.StringIO()
            environment = {'GITHUB_EVENT_PATH': str(event_path), 'GITHUB_EVENT_NAME': 'pull_request_target',
                           'GITHUB_REPOSITORY': REPOSITORY, 'GITHUB_RUN_ID': '123', 'DISPATCH_TOKEN': token}
            with patch.dict(os.environ, environment), patch('urllib.request.urlopen', return_value=response,
                                                          side_effect=error) as send, contextlib.redirect_stdout(output):
                failure = None
                try:
                    exec(self.script, {})
                except SystemExit as exception:
                    failure = exception.code
            return send, output.getvalue(), failure

    def test_ready_opened_and_synchronize_request_validation_only(self):
        for action in ['ready_for_review', 'opened', 'synchronize', 'reopened', 'edited']:
            with self.subTest(action=action):
                event = copy.deepcopy(self.event)
                event['action'] = action
                send, output, failure = self.run_event(event)
                self.assertIsNone(failure)
                request = send.call_args.args[0]
                self.assertEqual(request.full_url, 'https://api.github.com/repos/PinedaTec-EU/pinedatec-ci/dispatches')
                payload = json.loads(request.data)
                self.assertEqual(payload['event_type'], 'private-release-ledger')
                self.assertEqual(payload['client_payload'], {'target_repository': REPOSITORY,
                    'operation': 'validate', 'pilot_request_id': 'leonardo-pr65-run123'})
                self.assertNotIn('fake-dispatch-token', output)

    def test_drafts_forks_non_main_and_unrelated_events_never_dispatch(self):
        variants = []
        for action in ['closed', 'converted_to_draft']:
            event = copy.deepcopy(self.event)
            event['action'] = action
            variants.append(event)
        for field, value in [('draft', True), ('state', 'closed')]:
            event = copy.deepcopy(self.event)
            event['pull_request'][field] = value
            variants.append(event)
        event = copy.deepcopy(self.event)
        event['pull_request']['head']['repo']['full_name'] = 'someone/fork'
        variants.append(event)
        event = copy.deepcopy(self.event)
        event['pull_request']['base']['ref'] = 'other'
        variants.append(event)
        for event in variants:
            send, _, failure = self.run_event(event)
            send.assert_not_called()
            self.assertEqual(failure, 0)

    def test_missing_token_fails_without_dispatch(self):
        send, _, failure = self.run_event(self.event, token='')
        send.assert_not_called()
        self.assertEqual(failure, 'PINEDATEC_CI_DISPATCH_TOKEN is required.')

    def test_http_error_fails_without_leaking_response_or_token(self):
        error = urllib.error.HTTPError('https://api.github.com', 403, 'fake-dispatch-token', {}, None)
        _, output, failure = self.run_event(self.event, error=error)
        self.assertEqual(failure, 'Dispatch failed with HTTP 403.')
        self.assertNotIn('fake-dispatch-token', output + str(failure))

    def test_credentialed_workflow_never_checks_out_candidate(self):
        workflow = WORKFLOW.read_text()
        self.assertNotIn('uses:', workflow)
        self.assertNotIn('actions/checkout', workflow)
        self.assertIn('pull_request_target:', workflow)
        self.assertIn("python3 -I - <<'PYTHON'", workflow)


if __name__ == '__main__':
    unittest.main()

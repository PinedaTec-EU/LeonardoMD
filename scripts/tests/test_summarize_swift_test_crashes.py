import json
import tempfile
import time
import unittest
from pathlib import Path

from scripts.summarize_swift_test_crashes import collect_summaries, summarize_report


class SwiftTestCrashSummaryTests(unittest.TestCase):
    def test_ips_summary_keeps_crash_signature_without_private_paths(self):
        with tempfile.TemporaryDirectory() as temporary:
            report = Path(temporary) / "LeonardoMDPackageTests-2026.ips"
            report.write_text(
                json.dumps({"app_name": "LeonardoMDPackageTests"})
                + "\n"
                + json.dumps(
                    {
                        "procName": "LeonardoMDPackageTests",
                        "exception": {"type": "EXC_CRASH", "signal": "SIGABRT"},
                        "termination": {"namespace": "SIGNAL", "code": 6, "indicator": "Abort trap"},
                        "faultingThread": 2,
                        "threads": [
                            {"id": 2, "frames": [
                                {"imageName": "libswiftCore.dylib", "symbol": "swift_runtime_on_report"}
                            ]}
                        ],
                        "privatePath": "/Users/alice/private/secret.txt",
                    }
                ),
                encoding="utf-8",
            )

            summary = summarize_report(report)

        self.assertIn("process=LeonardoMDPackageTests", summary)
        self.assertIn("exception=EXC_CRASH SIGABRT", summary)
        self.assertIn("termination=SIGNAL 6 Abort trap", summary)
        self.assertIn("swift_runtime_on_report", summary)
        self.assertNotIn("/Users/alice", summary)
        self.assertNotIn("secret.txt", summary)

    def test_text_crash_summary_extracts_faulting_thread_frames(self):
        with tempfile.TemporaryDirectory() as temporary:
            report = Path(temporary) / "xctest-crash.crash"
            report.write_text(
                "Process: LeonardoAppTests [123]\n"
                "Exception Type: EXC_CRASH (SIGABRT)\n"
                "Termination Reason: Namespace SIGNAL, Code 6 Abort trap\n"
                "Thread 4 Crashed:\n"
                "0   libsystem_kernel.dylib 0x0000000100000000 __pthread_kill + 10\n"
                "1   libsystem_c.dylib 0x0000000100000001 abort + 12\n"
                "Thread 5:\n",
                encoding="utf-8",
            )

            summary = summarize_report(report)

        self.assertIn("process=LeonardoAppTests _123_", summary)
        self.assertIn("faulting_thread=4", summary)
        self.assertIn("__pthread_kill", summary)
        self.assertIn("abort", summary)

    def test_collection_excludes_old_and_unrelated_reports(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            old = directory / "swift-old.ips"
            old.write_text("{}", encoding="utf-8")
            unrelated = directory / "Finder.crash"
            unrelated.write_text("Exception Type: EXC_CRASH", encoding="utf-8")
            recent = directory / "xctest-current.crash"
            recent.write_text("Exception Type: EXC_CRASH", encoding="utf-8")
            old.touch()
            started_after = time.time()
            recent.touch()

            summaries = collect_summaries(directory, started_after)

        self.assertEqual(len(summaries), 1)
        self.assertIn("xctest-current.crash", summaries[0])
        self.assertNotIn("swift-old.ips", summaries[0])


if __name__ == "__main__":
    unittest.main()

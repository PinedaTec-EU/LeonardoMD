import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("prime_sparkle_cache", Path(__file__).resolve().parents[1] / "prime-sparkle-cache.py")
CACHE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CACHE)


class SparkleCacheTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.cache = self.root / "cache"
        self.payload = b"synthetic verified artifact"
        self.pin = {"identity": "sparkle", "location": "https://github.com/sparkle-project/Sparkle",
                    "state": {"revision": CACHE.REVISION, "version": CACHE.VERSION}}
        self.write_pin()
        for key, value in (("SIZE", len(self.payload)), ("CHECKSUM", hashlib.sha256(self.payload).hexdigest())):
            patcher = patch.object(CACHE, key, value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def write_pin(self):
        (self.root / "Package.resolved").write_text(json.dumps({"pins": [self.pin]}))

    def test_verified_download_is_reused_without_network(self):
        unrelated = self.root / "other-dependency"
        unrelated.write_bytes(b"keep")
        target = CACHE.prime(self.root, self.cache, lambda path: path.write_bytes(self.payload))
        self.assertEqual(target.read_bytes(), self.payload)
        CACHE.prime(self.root, self.cache, lambda _: self.fail("Verified cache must not download"))
        self.assertEqual(unrelated.read_bytes(), b"keep")
        self.assertEqual(list(self.cache.iterdir()), [target])

    def test_tampered_download_preserves_previous_entry_and_cleans_staging(self):
        self.cache.mkdir()
        target = self.cache / CACHE.CACHE_NAME
        target.write_bytes(b"previous incomplete entry")
        with self.assertRaisesRegex(ValueError, "checksum mismatch"):
            CACHE.prime(self.root, self.cache, lambda path: path.write_bytes(b"X" * len(self.payload)))
        self.assertEqual(target.read_bytes(), b"previous incomplete entry")
        self.assertEqual(list(self.cache.iterdir()), [target])

    def test_wrong_length_is_not_published(self):
        with self.assertRaisesRegex(ValueError, "checksum mismatch"):
            CACHE.prime(self.root, self.cache, lambda path: path.write_bytes(b"short"))
        self.assertEqual(list(self.cache.iterdir()), [])

    def test_changed_pin_fails_before_network_or_cache_write(self):
        self.pin["state"]["revision"] = "0" * 40
        self.write_pin()
        with self.assertRaisesRegex(ValueError, "pin changed"):
            CACHE.prime(self.root, self.cache, lambda _: self.fail("Changed pin must not download"))
        self.assertFalse(self.cache.exists())

    def test_symlinked_entry_is_rejected_without_touching_target(self):
        self.cache.mkdir()
        original = self.root / "original"
        original.write_bytes(b"keep")
        (self.cache / CACHE.CACHE_NAME).symlink_to(original)
        with self.assertRaisesRegex(ValueError, "symlinked"):
            CACHE.prime(self.root, self.cache, lambda _: self.fail("Symlink must not download"))
        self.assertEqual(original.read_bytes(), b"keep")

    def test_api_failure_does_not_publish_partial_bytes(self):
        def fail(path):
            path.write_bytes(b"partial")
            raise ValueError("download failed")
        with self.assertRaisesRegex(ValueError, "download failed"):
            CACHE.prime(self.root, self.cache, fail)
        self.assertEqual(list(self.cache.iterdir()), [])


if __name__ == "__main__":
    unittest.main()

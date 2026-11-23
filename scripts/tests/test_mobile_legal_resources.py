"""Keep the offline mobile legal disclosures in step with vendored renderer assets."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class MobileLegalResourcesTests(unittest.TestCase):
    def test_offline_disclosures_match_canonical_sources(self):
        mobile = ROOT / "Mobile/LittleLeonardo/Legal"
        self.assertEqual((mobile / "LICENSE.txt").read_bytes(), (ROOT / "LICENSE").read_bytes())

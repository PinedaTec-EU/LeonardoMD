"""Keep the offline mobile legal disclosures in step with vendored renderer assets."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class MobileLegalResourcesTests(unittest.TestCase):
    def test_offline_disclosures_match_canonical_sources(self):
        mobile = ROOT / "Mobile/LittleLeonardo/Legal"
        renderer = ROOT / "Sources/LeonardoRender/Resources"
        self.assertEqual((mobile / "LICENSE.txt").read_bytes(), (ROOT / "LICENSE").read_bytes())
        self.assertEqual((mobile / "THIRD_PARTY_NOTICES.txt").read_bytes(),
                         (renderer / "THIRD_PARTY_NOTICES.txt").read_bytes())
        sources = {p.name: p.read_bytes() for p in (renderer / "licenses").glob("*.txt")}
        copies = {p.name: p.read_bytes() for p in (mobile / "licenses").glob("*.txt")}
        self.assertTrue(sources)
        self.assertEqual(copies, sources)

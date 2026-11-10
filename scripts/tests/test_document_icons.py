import plistlib
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class DocumentIconTests(unittest.TestCase):
    def test_supported_types_reference_packaged_icon_without_branding_plain_text(self):
        with (ROOT / 'scripts/Info.plist').open('rb') as stream:
            info = plistlib.load(stream)
        declarations = {uti: entry for entry in info['CFBundleDocumentTypes']
                        for uti in entry['LSItemContentTypes']}
        for uti in ('net.daringfireball.markdown', 'eu.pinedatec.leonardomd.mdlf',
                    'eu.pinedatec.leonardomd.mdlr', 'eu.pinedatec.leonardomd.mdlz'):
            icon = declarations[uti]['CFBundleTypeIconFile']
            self.assertTrue((ROOT / 'assets/AppIcon' / icon).is_file())
        self.assertNotIn('CFBundleTypeIconFile', declarations['public.plain-text'])


if __name__ == '__main__':
    unittest.main()

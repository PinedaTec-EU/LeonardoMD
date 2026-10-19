from __future__ import annotations

import json
import stat
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path


SCRIPT_DIRECTORY = Path(__file__).parents[1] / "skills" / "leonardo-format" / "scripts"
sys.path.insert(0, str(SCRIPT_DIRECTORY))

import mdlz  # noqa: E402


DOCUMENT = """---
{
  \"format\": \"mdlf\",
  \"formatVersion\": 1,
  \"document\": {\"kind\": \"form\"},
  \"fields\": {\"name\": {\"type\": \"text\"}},
  \"values\": {}
}
---

# {{field:name}}
"""


class MDLZHelperTests(unittest.TestCase):
    def test_limits_match_the_swift_transport_envelope(self) -> None:
        self.assertEqual(mdlz.MAX_ARCHIVE_BYTES, 64 * 1024 * 1024)
        self.assertEqual(mdlz.MAX_ENTRIES, 2_048)
        self.assertEqual(mdlz.MAX_TOTAL_BYTES, 128 * 1024 * 1024)

    def test_pack_inspect_extract_round_trip(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            assets = source / "assets" / "nested"
            assets.mkdir(parents=True)
            (source / "request.mdlf").write_text(DOCUMENT, encoding="utf-8")
            (source / "assets" / "logo.txt").write_text("logo", encoding="utf-8")
            (assets / "seal.txt").write_text("seal", encoding="utf-8")

            archive = root / "request.mdlz"
            result = mdlz.pack_directory(source, archive)
            self.assertEqual(result["document"], "request.mdlf")
            inspected = mdlz.inspect_archive(archive)
            self.assertEqual(inspected["document"], "request.mdlf")
            self.assertEqual(
                {entry["path"] for entry in inspected["entries"]},
                {"assets", "assets/logo.txt", "assets/nested", "assets/nested/seal.txt", "request.mdlf"},
            )

            destination = root / "extracted"
            extracted = mdlz.extract_archive(archive, destination)
            self.assertEqual(extracted["document"], "request.mdlf")
            self.assertEqual((destination / "request.mdlf").read_text(encoding="utf-8"), DOCUMENT)
            self.assertEqual((destination / "assets" / "nested" / "seal.txt").read_text(), "seal")

    def test_pack_is_deterministic(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            (source / "assets").mkdir(parents=True)
            (source / "form.mdlr").write_text(DOCUMENT, encoding="utf-8")
            (source / "assets" / "image.bin").write_bytes(bytes(range(32)))
            first = root / "first.mdlz"
            second = root / "second.mdlz"
            mdlz.pack_directory(source, first)
            mdlz.pack_directory(source, second)
            self.assertEqual(first.read_bytes(), second.read_bytes())

    def test_pack_rejects_multiple_documents_and_root_files(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            source.mkdir()
            (source / "one.mdlf").write_text(DOCUMENT, encoding="utf-8")
            (source / "two.mdlr").write_text(DOCUMENT, encoding="utf-8")
            with self.assertRaisesRegex(mdlz.ArchiveError, "exactly one"):
                mdlz.pack_directory(source, root / "out.mdlz")

            (source / "two.mdlr").unlink()
            (source / "notes.txt").write_text("not an asset", encoding="utf-8")
            with self.assertRaisesRegex(mdlz.ArchiveError, "below assets"):
                mdlz.pack_directory(source, root / "out.mdlz")

    def test_pack_rejects_symlink_assets(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            (source / "assets").mkdir(parents=True)
            (source / "form.mdlf").write_text(DOCUMENT, encoding="utf-8")
            outside = root / "outside.txt"
            outside.write_text("outside", encoding="utf-8")
            (source / "assets" / "linked.txt").symlink_to(outside)
            with self.assertRaisesRegex(mdlz.ArchiveError, "symlink"):
                mdlz.pack_directory(source, root / "out.mdlz")

    def test_extract_rejects_traversal_and_symlink_entries(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            traversal = root / "traversal.mdlz"
            with zipfile.ZipFile(traversal, "w") as archive:
                archive.writestr("../escape.mdlf", DOCUMENT)
            with self.assertRaisesRegex(mdlz.ArchiveError, "canonical relative"):
                mdlz.inspect_archive(traversal)

            linked = root / "linked.mdlz"
            symlink = zipfile.ZipInfo("assets/link")
            symlink.external_attr = stat.S_IFLNK << 16
            with zipfile.ZipFile(linked, "w") as archive:
                archive.writestr(symlink, "outside")
                archive.writestr("form.mdlf", DOCUMENT)
            with self.assertRaisesRegex(mdlz.ArchiveError, "symlink"):
                mdlz.inspect_archive(linked)

            compressed = root / "compressed.mdlz"
            with zipfile.ZipFile(compressed, "w", compression=zipfile.ZIP_BZIP2) as archive:
                archive.writestr("form.mdlf", DOCUMENT)
            with self.assertRaisesRegex(mdlz.ArchiveError, "compression method"):
                mdlz.inspect_archive(compressed)

    def test_extract_rejects_collisions_and_existing_destination(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive_path = root / "collision.mdlz"
            with zipfile.ZipFile(archive_path, "w") as archive:
                archive.writestr("form.mdlf", DOCUMENT)
                archive.writestr("assets/A.txt", "a")
                archive.writestr("assets/a.txt", "b")
            with self.assertRaisesRegex(mdlz.ArchiveError, "colliding"):
                mdlz.inspect_archive(archive_path)

            source = root / "source"
            (source / "assets").mkdir(parents=True)
            (source / "form.mdlf").write_text(DOCUMENT, encoding="utf-8")
            valid = root / "valid.mdlz"
            mdlz.pack_directory(source, valid)
            destination = root / "destination"
            destination.mkdir()
            with self.assertRaisesRegex(mdlz.ArchiveError, "already exists"):
                mdlz.extract_archive(valid, destination)

            with self.assertRaisesRegex(mdlz.ArchiveError, "outside the limit"):
                mdlz.inspect_archive(valid, mdlz.Limits(max_archive_bytes=1))

    def test_document_validation_checks_utf8_and_format_envelope(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            document = root / "document.mdlf"
            document.write_text(DOCUMENT, encoding="utf-8")
            result = mdlz.validate_document(document)
            self.assertTrue(result["utf8"])
            self.assertEqual(result["extension"], ".mdlf")
            self.assertEqual(result["format"], "mdlf")
            self.assertEqual(result["formatVersion"], 1)
            self.assertEqual(result["documentKind"], "form")

            invalid = root / "invalid.mdlf"
            invalid.write_bytes(b"\xff")
            with self.assertRaisesRegex(mdlz.ArchiveError, "UTF-8"):
                mdlz.validate_document(invalid)

            unsupported = root / "unsupported.mdlf"
            unsupported.write_text(DOCUMENT.replace('"formatVersion": 1', '"formatVersion": 99'), encoding="utf-8")
            with self.assertRaisesRegex(mdlz.ArchiveError, "unsupported"):
                mdlz.validate_document(unsupported)

    def test_mdlr_extension_is_only_an_opening_mode_hint(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            document = root / "document.mdlr"
            document.write_text(DOCUMENT.replace('"kind": "form"', '"kind": "document"'), encoding="utf-8")

            result = mdlz.validate_document(document)

            self.assertEqual(result["extension"], ".mdlr")
            self.assertEqual(result["documentKind"], "document")

    def test_duplicate_front_matter_keys_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            document = Path(temporary) / "duplicate.mdlf"
            document.write_text(
                "---\n"
                '{"format": "mdlf", "format": "mdlf", "formatVersion": 1}\n'
                "---\n\n# Duplicate\n",
                encoding="utf-8",
            )

            with self.assertRaisesRegex(mdlz.ArchiveError, "duplicate metadata key"):
                mdlz.validate_document(document)

    def test_schema_validation_is_optional_and_explicit(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            document = root / "document.mdlf"
            document.write_text(DOCUMENT, encoding="utf-8")
            schema = root / "schema.json"
            schema.write_text(
                json.dumps({"type": "object", "required": ["format"]}),
                encoding="utf-8",
            )
            try:
                import jsonschema  # noqa: F401
            except ImportError:
                with self.assertRaisesRegex(mdlz.ArchiveError, "optional Python package 'jsonschema'"):
                    mdlz.validate_document(document, schema_path=schema)
            else:
                result = mdlz.validate_document(document, schema_path=schema)
                self.assertEqual(result["semanticValidation"], "jsonschema")


if __name__ == "__main__":
    unittest.main()

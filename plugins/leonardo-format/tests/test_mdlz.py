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
    def write_archive(self, path: Path, document: str, content: str) -> None:
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr(document, content)

    def test_limits_match_the_swift_transport_envelope(self) -> None:
        self.assertEqual(mdlz.MAX_ARCHIVE_BYTES, 64 * 1024 * 1024)
        self.assertEqual(mdlz.MAX_ENTRIES, 2_048)
        self.assertEqual(mdlz.MAX_MEMBER_BYTES, 32 * 1024 * 1024)
        self.assertEqual(mdlz.MAX_TOTAL_BYTES, 32 * 1024 * 1024)

    def test_pack_rejects_more_than_the_transport_entry_limit(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            assets = source / "assets"
            assets.mkdir(parents=True)
            (source / "request.mdlf").write_text(DOCUMENT, encoding="utf-8")
            for index in range(mdlz.MAX_ENTRIES):
                (assets / f"{index}.txt").write_bytes(b"")
            with self.assertRaisesRegex(mdlz.ArchiveError, "too many entries"):
                mdlz.pack_directory(source, root / "request.mdlz")

    def test_pack_inspect_extract_round_trip(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            assets = source / "assets" / "nested"
            assets.mkdir(parents=True)
            (source / "empty-directory").mkdir()
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
                {"assets/logo.txt", "assets/nested/seal.txt", "request.mdlf"},
            )

            destination = root / "extracted"
            extracted = mdlz.extract_archive(archive, destination)
            self.assertEqual(extracted["document"], "request.mdlf")
            self.assertEqual((destination / "request.mdlf").read_text(encoding="utf-8"), DOCUMENT)
            self.assertEqual((destination / "assets" / "nested" / "seal.txt").read_text(), "seal")

    def test_empty_directory_records_are_nonsemantic(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / "directories.mdlz"
            with zipfile.ZipFile(archive, "w") as handle:
                handle.writestr("assets/", b"")
                handle.writestr("document.mdlf", DOCUMENT)

            inspected = mdlz.inspect_archive(archive)
            self.assertEqual({entry["path"] for entry in inspected["entries"]}, {"document.mdlf"})
            destination = root / "extracted"
            mdlz.extract_archive(archive, destination)
            self.assertFalse((destination / "assets").exists())

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

    def test_unicode_casefold_collisions_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for index, names in enumerate((("assets/ß", "assets/ss"), ("assets/σ", "assets/ς"))):
                archive = root / f"collision-{index}.mdlz"
                with zipfile.ZipFile(archive, "w") as handle:
                    handle.writestr("document.mdlf", DOCUMENT)
                    for name in names:
                        handle.writestr(name, b"x")
                with self.assertRaisesRegex(mdlz.ArchiveError, "colliding"):
                    mdlz.inspect_archive(archive)

            archive = root / "parent-collision.mdlz"
            with zipfile.ZipFile(archive, "w") as handle:
                handle.writestr("document.mdlf", DOCUMENT)
                handle.writestr("assets/σ", b"x")
                handle.writestr("assets/ς/child", b"y")
            with self.assertRaisesRegex(mdlz.ArchiveError, "conflicting parent"):
                mdlz.inspect_archive(archive)

    def test_package_limits_reject_more_than_32_mib_expanded(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            oversized = ("---\n"
                         '{"format": "mdlf", "formatVersion": 1}\n'
                         "---\n") + ("x" * (32 * 1024 * 1024))
            document = root / "oversized.mdlf"
            document.write_text(oversized, encoding="utf-8")
            with self.assertRaisesRegex(mdlz.ArchiveError, "too large"):
                mdlz.validate_document(document)

            archive = root / "oversized.mdlz"
            with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_STORED) as handle:
                handle.writestr("oversized.mdlf", oversized.encode("utf-8"))
            with self.assertRaisesRegex(mdlz.ArchiveError, "too large|expands"):
                mdlz.inspect_archive(archive)

    def test_archive_commands_reject_invalid_root_before_effects(self) -> None:
        invalid_documents = {
            "future": DOCUMENT.replace('"formatVersion": 1', '"formatVersion": 2'),
            "malformed": "# no Leonardo front matter\n",
            "duplicate": (
                "---\n"
                '{"format": "mdlf", "format": "mdlf", "formatVersion": 1}\n'
                "---\n\n# Duplicate\n"
            ),
            "unknown": DOCUMENT.replace('  "values": {}\n', '  "values": {},\n  "unexpected": true\n'),
        }
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name, content in invalid_documents.items():
                archive = root / f"{name}.mdlz"
                self.write_archive(archive, "document.mdlf", content)

                with self.assertRaises(mdlz.ArchiveError):
                    mdlz.inspect_archive(archive)

                destination = root / f"{name}-extracted"
                with self.assertRaises(mdlz.ArchiveError):
                    mdlz.extract_archive(archive, destination)
                self.assertFalse(destination.exists(), name)

            source = root / "invalid-source"
            source.mkdir()
            (source / "document.mdlf").write_text(invalid_documents["unknown"], encoding="utf-8")
            output = root / "invalid-source.mdlz"
            with self.assertRaises(mdlz.ArchiveError):
                mdlz.pack_directory(source, output)
            self.assertFalse(output.exists())
            self.assertEqual(list(root.glob(".invalid-source.mdlz.mdlz-pack-*")), [])

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

    def test_bundled_schema_rejects_unknown_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            document = Path(temporary) / "unknown.mdlf"
            document.write_text(
                DOCUMENT.replace('  "values": {}\n', '  "values": {},\n  "unexpected": true\n'),
                encoding="utf-8",
            )

            with self.assertRaisesRegex(mdlz.ArchiveError, "unknown property"):
                mdlz.validate_document(document)

    def test_shared_semantic_fixtures_match_the_native_contract(self) -> None:
        fixtures = Path(__file__).parents[3] / "Tests" / "FormatContractFixtures"
        for document in sorted((fixtures / "valid").glob("*.mdlf")):
            self.assertEqual(mdlz.validate_document(document)["formatVersion"], 1, document.name)
        for document in sorted((fixtures / "invalid").glob("*.mdlf")):
            with self.assertRaises(mdlz.ArchiveError, msg=document.name):
                mdlz.validate_document(document)

    def test_metadata_semantics_reject_unsafe_definitions_but_keep_draft_values_opaque(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)

            def write(name: str, metadata: dict[str, object]) -> Path:
                path = root / name
                path.write_text(
                    "---\n" + json.dumps(metadata, ensure_ascii=False) + "\n---\nBody\n",
                    encoding="utf-8",
                )
                return path

            cases = {
                "length.mdlf": {
                    "format": "mdlf",
                    "formatVersion": 1,
                    "fields": {"name": {"type": "text", "minLength": 4, "maxLength": 2}},
                },
                "number.mdlf": {
                    "format": "mdlf",
                    "formatVersion": 1,
                    "fields": {"amount": {"type": "number", "minimum": 10, "maximum": 2}},
                },
                "options.mdlf": {
                    "format": "mdlf",
                    "formatVersion": 1,
                    "fields": {"choice": {"type": "select", "options": [{"value": "a"}, {"value": "a"}]}},
                },
                "pattern.mdlf": {
                    "format": "mdlf",
                    "formatVersion": 1,
                    "fields": {"name": {"type": "text", "pattern": "(a+)+"}},
                },
                "pattern-length.mdlf": {
                    "format": "mdlf",
                    "formatVersion": 1,
                    "fields": {"name": {"type": "text", "pattern": "é" * 257}},
                },
                "pattern-invalid.mdlf": {
                    "format": "mdlf",
                    "formatVersion": 1,
                    "fields": {"name": {"type": "text", "pattern": "["}},
                },
                "asset.mdlf": {
                    "format": "mdlf",
                    "formatVersion": 1,
                    "layout": {"background": {"image": "../outside.png"}},
                },
            }
            for name, metadata in cases.items():
                with self.assertRaises(mdlz.ArchiveError, msg=name):
                    mdlz.validate_document(write(name, metadata))

            draft = Path(__file__).parents[3] / "Tests" / "FormatContractFixtures" / "valid" / "draft-invalid-values.mdlf"
            self.assertEqual(mdlz.validate_document(draft)["formatVersion"], 1)

    def test_schema_evaluator_fails_closed_on_unknown_assertions(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            document = root / "document.mdlf"
            document.write_text(DOCUMENT, encoding="utf-8")
            schema = root / "schema.json"
            schema.write_text(json.dumps({"type": "object", "unevaluatedProperties": False}), encoding="utf-8")

            with self.assertRaisesRegex(mdlz.ArchiveError, "unsupported keyword"):
                mdlz.validate_document(document, schema_path=schema)

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
            result = mdlz.validate_document(document, schema_path=schema)
            self.assertEqual(result["semanticValidation"], "bundled-schema+external")


if __name__ == "__main__":
    unittest.main()

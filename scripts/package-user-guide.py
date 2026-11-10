#!/usr/bin/env python3
"""Build deterministic offline guide packages with the canonical MDLZ validator."""
import argparse
import json
import shutil
from pathlib import Path
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
HELPERS = ROOT / "plugins/leonardo-format/skills/leonardo-format/scripts"
sys.path.insert(0, str(HELPERS))
import mdlz


LANGUAGES = ("en", "es")


def practice_metadata(language):
    spanish = language == "es"
    return {
        "format": "mdlf", "formatVersion": 1,
        "document": {"id": "leonardo-practice-" + language, "kind": "form", "revision": 1},
        "fields": {
            "practiceName": {"type": "text", "maxLength": 80, "label": "Nombre de prueba" if spanish else "Practice name"},
            "practiceGoal": {"type": "multiline", "maxLength": 1000, "label": "Tu objetivo" if spanish else "Your goal"},
            "practiceReady": {"type": "checkbox", "label": "Listo para compartir" if spanish else "Ready to share"},
        },
        "values": {"practiceName": None, "practiceGoal": None, "practiceReady": False},
    }


def metadata(language):
    return {"format": "mdlf", "formatVersion": 1,
            "document": {"id": "leonardo-user-guide-" + language, "kind": "document", "revision": 31},
            "layout": {"images": [{"source": "assets/graphic-inspector.png", "size": {"width": {"value": 240, "unit": "points"}}}]}}


def practice_source(language):
    body = (ROOT / "doc/guide" / language / "practice.md").read_text(encoding="utf-8")
    return '---\n' + json.dumps(practice_metadata(language), ensure_ascii=False, indent=2) + '\n---\n' + body


def build(language, destination):
    with tempfile.TemporaryDirectory(prefix="leonardo-guide-") as temporary:
        staging = Path(temporary)
        assets = staging / "assets"
        assets.mkdir()
        shutil.copyfile(ROOT / "doc/guide/cover.png", assets / "cover.png")
        # Only PNG content assets belong in the package, not provenance/QA sidecars.
        for image in sorted((ROOT / "doc/guide" / language / "assets").glob("*.png")):
            if image.is_symlink() or not image.is_file():
                raise ValueError(f"Guide image must be a regular file: {image.name}")
            shutil.copyfile(image, assets / image.name)
        body = (ROOT / "doc/guide" / language / "body.md").read_text(encoding="utf-8")
        (staging / "guide.mdlf").write_text('---\n' + json.dumps(metadata(language), ensure_ascii=False, indent=2)
                                            + '\n---\n' + body, encoding="utf-8")
        mdlz.pack_directory(staging, destination)


def build_agent_import(language, destination):
    """Derive the standalone guide from the same main-help chapter."""
    body = (ROOT / "doc/guide" / language / "body.md").read_text(encoding="utf-8")
    section = body.split("<!-- agent-import:begin -->\n", 1)[1].split("<!-- agent-import:end -->", 1)[0]
    section = section.replace("### ", "# ", 1).replace("\n#### ", "\n## ")
    name = "importar" if language == "es" else "import"
    header = {"format": "mdlf", "formatVersion": 1,
              "document": {"id": "leonardo-agent-import-" + language, "kind": "document", "revision": 3}}
    with tempfile.TemporaryDirectory(prefix="leonardo-agent-import-") as temporary:
        staging = Path(temporary)
        (staging / "assets").mkdir()
        shutil.copyfile(ROOT / "doc/guide" / language / "assets" / (name + ".png"),
                        staging / "assets" / (name + ".png"))
        (staging / "guide.mdlf").write_text('---\n' + json.dumps(header, ensure_ascii=False, indent=2)
                                            + '\n---\n' + section, encoding="utf-8")
        mdlz.pack_directory(staging, destination)


def write_web_guide(language, directory):
    """Generate the reading edition without pretending GitHub has form controls."""
    body = (ROOT / "doc/guide" / language / "body.md").read_text(encoding="utf-8")
    cover, rest = body.split("\n", 1)
    intro, rest = rest.split("\n## ", 1)
    # Keep introductory artwork while omitting native personal-copy instructions.
    rest = "\n\n".join(line for line in intro.splitlines() if line.startswith("![")) + "\n\n## " + rest
    spanish = language == "es"
    title = "Guía de Leonardo" if spanish else "Leonardo user guide"
    notice = ("Edición web de lectura. Abre Ayuda → Guía de Leonardo en la app para usar "
              "el formulario de práctica independiente y los ejemplos renderizados con las extensiones "
              "correspondientes. Este lector web puede no interpretar Mermaid, KaTeX o Vega-Lite."
              if spanish else
              "Web reading edition. Open Help → Leonardo user guide in the app to use "
              "the separate practice form and examples rendered with their required extensions. "
              "This web reader may not interpret Mermaid, KaTeX or Vega-Lite.")
    switch = "[English](user-guide.md) · [Español](user-guide-es.md)"
    # The source stays authoritative; web only adapts transport paths and controls.
    body = cover.replace("assets/cover.png", "../Sources/LeonardoApp/Resources/AboutBanner.png")
    body += f"\n\n# {title}\n\n{switch}\n\n{notice}\n" + rest
    # Ordinary web Markdown displays these placeholders literally. Leave all
    # source bytes intact, including copyable MDLF examples inside code fences.
    body = body.replace("](assets/", f"](guide/{language}/assets/")
    practice = directory / "guide" / language / "practice.mdlr"
    practice.parent.mkdir(parents=True, exist_ok=True)
    practice.write_text(practice_source(language), encoding="utf-8")
    name = "user-guide-es.md" if spanish else "user-guide.md"
    (directory / name).write_text("<!-- Generated from doc/guide; edit bilingual body.md sources. -->\n" + body, encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "Sources/LeonardoApp/Resources")
    parser.add_argument("--web-output", type=Path,
                        help="Also regenerate the English/Spanish web manuals in this documentation directory")
    args = parser.parse_args()
    if args.web_output is not None:
        args.web_output.mkdir(parents=True, exist_ok=True)
        for language in LANGUAGES:
            write_web_guide(language, args.web_output)
    args.output.mkdir(parents=True, exist_ok=True)
    for language in LANGUAGES:
        destination = args.output / f"Guide-v31-{language}.mdlz"
        # The canonical packer deliberately refuses overwrites. Replace only our generated artifact.
        with tempfile.TemporaryDirectory(prefix="leonardo-guide-output-") as temporary:
            result = Path(temporary) / destination.name
            build(language, result)
            destination.write_bytes(result.read_bytes())
        print(destination)
        agent_import = args.output / f"AgentImport-v3-{language}.mdlz"
        with tempfile.TemporaryDirectory(prefix="leonardo-import-output-") as temporary:
            result = Path(temporary) / agent_import.name
            build_agent_import(language, result)
            agent_import.write_bytes(result.read_bytes())
        print(agent_import)
        practice = args.output / f"Practice-v1-{language}.mdlr"
        practice.write_text(practice_source(language), encoding="utf-8")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Build deterministic offline guide packages with the canonical MDLZ validator."""
import argparse
import json
from pathlib import Path
import sys
import tempfile
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parent.parent
HELPERS = ROOT / "plugins/leonardo-format/skills/leonardo-format/scripts"
sys.path.insert(0, str(HELPERS))
import mdlz


ILLUSTRATIONS = {
    "en": {
        "journey": ("Your document journey", ["Write · MDLF", "Fill · MDLR", "Share · MDLZ"]),
        "package": ("One portable package · MDLZ", ["guide.mdlf", "assets/ · images", "Definitions + answers"]),
        "export": ("Choose what the recipient needs", ["Edit / fill → MDLZ", "Read → Markdown", "Fixed pages → PDF"]),
    },
    "es": {
        "recorrido": ("El recorrido de tu documento", ["Escribir · MDLF", "Rellenar · MDLR", "Compartir · MDLZ"]),
        "paquete": ("Un paquete portable · MDLZ", ["guia.mdlf", "assets/ · imágenes", "Definición + respuestas"]),
        "exportar": ("Elige según el destinatario", ["Editar / rellenar → MDLZ", "Leer → Markdown", "Páginas fijas → PDF"]),
    },
}


def illustration(title, labels):
    cards = []
    for index, label in enumerate(labels):
        x = 30 + index * 350
        cards.append(f'<rect x="{x}" y="100" width="320" height="100" rx="16" fill="#fff"/>')
        cards.append(f'<text x="{x + 160}" y="158" text-anchor="middle" fill="#432333" font-size="21">{escape(label)}</text>')
        if index < 2:
            cards.append(f'<text x="{x + 325}" y="160" fill="#432333" font-size="25">→</text>')
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="240" viewBox="0 0 1080 240">'
            '<rect width="1080" height="240" rx="20" fill="#f1e8dd"/>'
            '<g font-family="Helvetica,Arial,sans-serif">'
            f'<text x="30" y="58" fill="#432333" font-size="30" font-weight="bold">{escape(title)}</text>'
            + ''.join(cards) + '</g></svg>\n')


def metadata(language):
    spanish = language == "es"
    return {
        "format": "mdlf", "formatVersion": 1,
        "document": {"id": "leonardo-user-guide-" + language, "kind": "form", "revision": 1},
        "fields": {
            "practiceName": {"type": "text", "maxLength": 80, "label": "Nombre de prueba" if spanish else "Practice name"},
            "practiceGoal": {"type": "multiline", "maxLength": 1000, "label": "Tu objetivo" if spanish else "Your goal"},
            "practiceReady": {"type": "checkbox", "label": "Listo para compartir" if spanish else "Ready to share"},
        },
        "values": {"practiceName": None, "practiceGoal": None, "practiceReady": False},
    }


def build(language, destination):
    with tempfile.TemporaryDirectory(prefix="leonardo-guide-") as temporary:
        staging = Path(temporary)
        assets = staging / "assets"
        assets.mkdir()
        for name, (title, labels) in ILLUSTRATIONS[language].items():
            (assets / (name + ".svg")).write_text(illustration(title, labels), encoding="utf-8")
        body = (ROOT / "doc/guide" / language / "body.md").read_text(encoding="utf-8")
        (staging / "guide.mdlf").write_text('---\n' + json.dumps(metadata(language), ensure_ascii=False, indent=2)
                                            + '\n---\n' + body, encoding="utf-8")
        mdlz.pack_directory(staging, destination)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "Sources/LeonardoApp/Resources")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    for language in ILLUSTRATIONS:
        destination = args.output / f"Guide-v1-{language}.mdlz"
        # The canonical packer deliberately refuses overwrites. Replace only our generated artifact.
        with tempfile.TemporaryDirectory(prefix="leonardo-guide-output-") as temporary:
            result = Path(temporary) / destination.name
            build(language, result)
            destination.write_bytes(result.read_bytes())
        print(destination)


if __name__ == "__main__":
    main()

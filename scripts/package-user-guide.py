#!/usr/bin/env python3
"""Build deterministic offline guide packages with the canonical MDLZ validator."""
import argparse
import json
import shutil
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
        "document": {"id": "leonardo-user-guide-" + language, "kind": "form", "revision": 4},
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
        shutil.copyfile(ROOT / "Sources/LeonardoApp/Resources/AboutBanner.png", assets / "cover.png")
        # Only original PNG content assets belong in the package, not QA sidecars.
        for image in sorted((ROOT / "doc/guide" / language / "assets").glob("*.png")):
            if image.is_symlink() or not image.is_file():
                raise ValueError(f"Guide image must be a regular file: {image.name}")
            shutil.copyfile(image, assets / image.name)
        body = (ROOT / "doc/guide" / language / "body.md").read_text(encoding="utf-8")
        (staging / "guide.mdlf").write_text('---\n' + json.dumps(metadata(language), ensure_ascii=False, indent=2)
                                            + '\n---\n' + body, encoding="utf-8")
        mdlz.pack_directory(staging, destination)


def write_web_guide(language, directory):
    """Generate the reading edition without pretending GitHub has form controls."""
    body = (ROOT / "doc/guide" / language / "body.md").read_text(encoding="utf-8")
    cover, rest = body.split("\n", 1)
    rest = rest[rest.index("\n## "):]
    spanish = language == "es"
    title = "Guía de Leonardo" if spanish else "Leonardo user guide"
    notice = ("Edición web de lectura. Abre Ayuda → Guía de Leonardo en la app para usar "
              "los controles del formulario y los ejemplos renderizados con las extensiones "
              "correspondientes. Este lector web puede no interpretar Mermaid, KaTeX o Vega-Lite."
              if spanish else
              "Web reading edition. Open Help → Leonardo user guide in the app to use "
              "the form controls and examples rendered with their required extensions. "
              "This web reader may not interpret Mermaid, KaTeX or Vega-Lite.")
    switch = "[English](user-guide.md) · [Español](user-guide-es.md)"
    # The source stays authoritative; web only adapts transport paths and controls.
    body = cover.replace("assets/cover.png", "../Sources/LeonardoApp/Resources/AboutBanner.png")
    body += f"\n\n# {title}\n\n{switch}\n\n{notice}\n" + rest
    # Ordinary web Markdown displays these placeholders literally. Leave all
    # source bytes intact, including copyable MDLF examples inside code fences.
    body = body.replace("](assets/", f"](guide/{language}/assets/")
    for name, (title, labels) in ILLUSTRATIONS[language].items():
        folder = directory / "guide" / "illustrations"
        folder.mkdir(parents=True, exist_ok=True)
        (folder / f"{language}-{name}.svg").write_text(illustration(title, labels), encoding="utf-8")
        body = body.replace(f"guide/{language}/assets/{name}.svg", f"guide/illustrations/{language}-{name}.svg")
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
        for language in ILLUSTRATIONS:
            write_web_guide(language, args.web_output)
    args.output.mkdir(parents=True, exist_ok=True)
    for language in ILLUSTRATIONS:
        destination = args.output / f"Guide-v4-{language}.mdlz"
        # The canonical packer deliberately refuses overwrites. Replace only our generated artifact.
        with tempfile.TemporaryDirectory(prefix="leonardo-guide-output-") as temporary:
            result = Path(temporary) / destination.name
            build(language, result)
            destination.write_bytes(result.read_bytes())
        print(destination)


if __name__ == "__main__":
    main()

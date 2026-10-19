#!/usr/bin/env python3
"""Dependency-free semantic checks shared by the Leonardo plugin readers."""

from __future__ import annotations

import math
import re
from urllib.parse import urlsplit


MAX_PATTERN_BYTES = 512
MAX_POINT_VALUE = 10_000.0
MAX_PERCENT_VALUE = 100.0
_GROUP_QUANTIFIER = re.compile(r"\)(?:[+*?]|\{\d)")
_BACKREFERENCE = re.compile(r"\\(?:[1-9]|k<)")


class MetadataSemanticError(ValueError):
    """A metadata definition violates a Leonardo v1 semantic rule."""


def _fail(path: str, message: str) -> None:
    raise MetadataSemanticError(f"metadata semantic validation failed at {path}: {message}")


def _finite_number(value: object) -> bool:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return False
    return isinstance(value, int) or math.isfinite(value)


def _basic_regex_syntax_is_valid(pattern: str) -> bool:
    """Catch malformed grouping before the host regex engine is invoked."""

    groups = 0
    in_character_class = False
    index = 0
    while index < len(pattern):
        character = pattern[index]
        if character == "\\":
            if index + 1 >= len(pattern):
                return False
            escaped = pattern[index + 1]
            if escaped in {"p", "P", "N"} and index + 2 < len(pattern) and pattern[index + 2] == "{":
                closing = pattern.find("}", index + 3)
                if closing < 0:
                    return False
                index = closing + 1
                continue
            index += 2
            continue
        if in_character_class:
            if character == "]":
                in_character_class = False
            index += 1
            continue
        if character == "[":
            in_character_class = True
        elif character == "(":
            groups += 1
        elif character == ")":
            if groups == 0:
                return False
            groups -= 1
        elif character == "{":
            closing = pattern.find("}", index + 1)
            if closing < 0:
                return False
            index = closing
        elif character == "}":
            return False
        index += 1
    return not in_character_class and groups == 0


def _uses_nonportable_syntax(pattern: str) -> bool:
    """Return whether a pattern uses a host-specific regex extension.

    MDLF v1 keeps the intersection of Python ``re`` and ICU's regular
    expression dialect. The pattern remains a declarative definition, so
    rejecting extensions here prevents a native app and an agent from giving
    different answers for the same document.
    """

    return any(
        marker in pattern
        for marker in (
            r"\p{", r"\P{", r"\X", r"\R", r"\N{",
            r"\A", r"\Z", r"\z",
            "(?<", "(?P<", "(?P=", "(?(", "(?>",
        )
    )


def _validate_pattern(value: object, path: str) -> None:
    if not isinstance(value, str):
        return
    if len(value.encode("utf-8")) > MAX_PATTERN_BYTES:
        _fail(path, "validation expressions are limited to 512 UTF-8 bytes")
    if any(fragment in value for fragment in ("(?=", "(?!", "(?<=", "(?<!")) or _BACKREFERENCE.search(value):
        _fail(path, "validation expressions cannot use backreferences or look-around constructs")
    if _GROUP_QUANTIFIER.search(value):
        _fail(path, "validation expressions cannot quantify groups")
    if _uses_nonportable_syntax(value):
        _fail(path, "validation expressions must use the portable v1 regular-expression subset")
    if not _basic_regex_syntax_is_valid(value):
        _fail(path, "validation expression is not a valid regular expression")
    try:
        re.compile(value)
    except re.error as exc:
        _fail(path, f"validation expression is not a valid regular expression: {exc}")


def _validate_asset_reference(value: object, path: str) -> None:
    if not isinstance(value, str):
        return
    reference = value.strip()
    if not reference:
        _fail(path, "asset references cannot be empty")
    if (
        reference.startswith("/")
        or "\\" in reference
        or any(ord(character) < 0x20 or ord(character) == 0x7F for character in reference)
        or any(part == ".." for part in reference.split("/"))
    ):
        _fail(path, "asset references must be relative paths or safe web URLs")
    try:
        scheme = urlsplit(reference).scheme.lower()
    except ValueError:
        scheme = ""
    if scheme and scheme not in {"http", "https"}:
        _fail(path, "asset references must be relative paths or safe web URLs")


def _validate_dimension(value: object, path: str, *, positive: bool) -> None:
    if not isinstance(value, dict):
        return
    number = value.get("value")
    unit = value.get("unit")
    if not _finite_number(number):
        _fail(path, "layout dimensions must be finite")
    if unit == "points":
        valid = 0 < number <= MAX_POINT_VALUE if positive else abs(number) <= MAX_POINT_VALUE
    elif unit == "percent":
        valid = 0 < number <= MAX_PERCENT_VALUE if positive else abs(number) <= MAX_PERCENT_VALUE
    else:
        return
    if not valid:
        _fail(path, f"layout dimension is outside the {unit} range (maximum {MAX_POINT_VALUE if unit == 'points' else MAX_PERCENT_VALUE})")


def _validate_offset(value: object, path: str) -> None:
    _validate_dimension(value, path, positive=False)


def _validate_position(value: object, path: str) -> None:
    if not isinstance(value, dict):
        return
    _validate_offset(value.get("x"), f"{path}.x")
    _validate_offset(value.get("y"), f"{path}.y")


def _validate_opacity(value: object, path: str) -> None:
    if value is None:
        return
    if not _finite_number(value) or not 0 <= value <= 1:
        _fail(path, "opacity must be between 0 and 1")


def _validate_field(definition: object, path: str) -> None:
    if not isinstance(definition, dict):
        return
    minimum_length = definition.get("minLength")
    maximum_length = definition.get("maxLength")
    if isinstance(minimum_length, int) and isinstance(maximum_length, int) and minimum_length > maximum_length:
        _fail(path, "minimum length cannot exceed maximum length")
    minimum = definition.get("minimum")
    maximum = definition.get("maximum")
    if _finite_number(minimum) and _finite_number(maximum) and minimum > maximum:
        _fail(path, "minimum cannot exceed maximum")
    if "pattern" in definition:
        _validate_pattern(definition["pattern"], f"{path}.pattern")

    options = definition.get("options")
    if isinstance(options, list):
        seen: set[str] = set()
        for index, option in enumerate(options):
            if not isinstance(option, dict) or not isinstance(option.get("value"), str):
                continue
            option_value = option["value"]
            if not option_value:
                _fail(f"{path}.options[{index}].value", "select options must have a value")
            if option_value in seen:
                _fail(f"{path}.options[{index}].value", "select options must be unique")
            seen.add(option_value)
        if definition.get("type") == "select" and not options:
            _fail(f"{path}.options", "a select field must declare at least one option")


def _validate_page(page: object, path: str) -> None:
    if not isinstance(page, dict):
        return
    margins = page.get("margins")
    if isinstance(margins, dict):
        for side in ("top", "right", "bottom", "left"):
            value = margins.get(side)
            if value is not None and (not _finite_number(value) or not 0 <= value <= MAX_POINT_VALUE):
                _fail(f"{path}.margins.{side}", "margins must be finite values between 0 and 10000 points")
    if page.get("size") == "custom":
        for dimension in ("widthPoints", "heightPoints"):
            value = page.get(dimension)
            if value is None or not _finite_number(value) or not 0 < value <= MAX_POINT_VALUE:
                _fail(f"{path}.{dimension}", "custom page dimensions must be greater than zero and at most 10000 points")


def _validate_layout(layout: object) -> None:
    if not isinstance(layout, dict):
        return
    _validate_page(layout.get("page"), "layout.page")

    background = layout.get("background")
    if isinstance(background, dict):
        _validate_opacity(background.get("opacity"), "layout.background.opacity")
        _validate_position(background.get("position"), "layout.background.position")
        _validate_asset_reference(background.get("image"), "layout.background.image")

    images = layout.get("images")
    if isinstance(images, list):
        occurrences: set[tuple[object, object]] = set()
        for index, image in enumerate(images):
            if not isinstance(image, dict):
                continue
            path = f"layout.images[{index}]"
            _validate_asset_reference(image.get("source"), f"{path}.source")
            occurrence = image.get("occurrence", 1)
            if isinstance(occurrence, int) and occurrence < 1:
                _fail(f"{path}.occurrence", "image occurrences are one-based")
            key = (image.get("source"), occurrence)
            if key in occurrences:
                _fail(path, "image layout entries must identify unique occurrences")
            occurrences.add(key)
            size = image.get("size")
            if isinstance(size, dict):
                _validate_dimension(size.get("width"), f"{path}.size.width", positive=True)
                _validate_dimension(size.get("height"), f"{path}.size.height", positive=True)
            _validate_position(image.get("position"), f"{path}.position")
            _validate_opacity(image.get("opacity"), f"{path}.opacity")

    tables = layout.get("tables")
    if isinstance(tables, list):
        occurrences: set[object] = set()
        for index, table in enumerate(tables):
            if not isinstance(table, dict):
                continue
            path = f"layout.tables[{index}]"
            occurrence = table.get("occurrence")
            if isinstance(occurrence, int) and occurrence < 1:
                _fail(f"{path}.occurrence", "table occurrences are one-based")
            if occurrence in occurrences:
                _fail(path, "table layout entries must identify unique occurrences")
            occurrences.add(occurrence)
            _validate_dimension(table.get("width"), f"{path}.width", positive=True)
            columns = table.get("columns")
            if isinstance(columns, list):
                for column_index, column in enumerate(columns):
                    if not isinstance(column, dict):
                        continue
                    column_path = f"{path}.columns[{column_index}]"
                    _validate_dimension(column.get("width"), f"{column_path}.width", positive=True)
                    _validate_dimension(column.get("minimumWidth"), f"{column_path}.minimumWidth", positive=True)
                    _validate_dimension(column.get("maximumWidth"), f"{column_path}.maximumWidth", positive=True)


def validate_metadata_semantics(metadata: dict[str, object]) -> None:
    """Validate definition/layout policy while leaving current values opaque."""

    fields = metadata.get("fields")
    if isinstance(fields, dict):
        for field_id, definition in fields.items():
            _validate_field(definition, f"fields.{field_id}")
    _validate_layout(metadata.get("layout"))

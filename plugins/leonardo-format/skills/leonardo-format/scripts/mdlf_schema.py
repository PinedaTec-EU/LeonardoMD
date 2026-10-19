#!/usr/bin/env python3
"""Dependency-free evaluator for the Leonardo MDLF JSON Schema subset."""

from __future__ import annotations

import json
import math
import re
from pathlib import Path


SCHEMA_ASSERTION_KEYWORDS = frozenset(
    {
        "$defs",
        "$ref",
        "additionalProperties",
        "const",
        "enum",
        "items",
        "maxLength",
        "maximum",
        "minLength",
        "minimum",
        "pattern",
        "properties",
        "propertyNames",
        "required",
        "type",
    }
)
SCHEMA_ANNOTATION_KEYWORDS = frozenset(
    {
        "$comment",
        "$id",
        "$schema",
        "default",
        "deprecated",
        "description",
        "examples",
        "readOnly",
        "title",
        "writeOnly",
    }
)
SCHEMA_KEYWORDS = SCHEMA_ASSERTION_KEYWORDS | SCHEMA_ANNOTATION_KEYWORDS
SCHEMA_TYPES = frozenset({"array", "boolean", "integer", "null", "number", "object", "string"})


class SchemaValidationError(ValueError):
    """The schema or metadata violates the supported MDLF contract."""


def _schema_location(path: tuple[str | int, ...]) -> str:
    location = "$"
    for item in path:
        location += f"[{item!r}]" if isinstance(item, str) else f"[{item}]"
    return location


def _schema_failure(path: tuple[str | int, ...], message: str) -> None:
    raise SchemaValidationError(f"schema validation failed at {_schema_location(path)}: {message}")


def _schema_definition_failure(location: str, message: str) -> None:
    raise SchemaValidationError(f"schema cannot be used for validation at {location}: {message}")


def _resolve_schema_reference(root: dict[str, object], reference: object) -> object:
    if not isinstance(reference, str) or not reference.startswith("#/$defs/"):
        _schema_definition_failure("$", f"unsupported $ref {reference!r}")
    key = reference[len("#/$defs/") :]
    if not key or "/" in key or "~" in key:
        _schema_definition_failure("$", f"unsupported $ref {reference!r}")
    definitions = root.get("$defs")
    if not isinstance(definitions, dict) or key not in definitions:
        _schema_definition_failure("$", f"unknown $ref {reference!r}")
    return definitions[key]


def _assert_supported_schema(
    schema: object,
    root: dict[str, object],
    location: str = "$",
    seen: set[int] | None = None,
) -> None:
    """Reject unsupported assertions before evaluating document metadata."""

    if isinstance(schema, bool):
        return
    if not isinstance(schema, dict):
        _schema_definition_failure(location, "schema must be an object or boolean")
    unknown = set(schema) - SCHEMA_KEYWORDS
    if unknown:
        names = ", ".join(sorted(str(item) for item in unknown))
        _schema_definition_failure(location, f"unsupported keyword(s): {names}")

    if "type" in schema:
        type_spec = schema["type"]
        type_names = [type_spec] if isinstance(type_spec, str) else type_spec if isinstance(type_spec, list) else None
        if not type_names or not all(isinstance(item, str) and item in SCHEMA_TYPES for item in type_names):
            _schema_definition_failure(location, f"unsupported type assertion: {type_spec!r}")
    if "required" in schema:
        required = schema["required"]
        if not isinstance(required, list) or not all(isinstance(item, str) for item in required):
            _schema_definition_failure(location, "required must be an array of strings")
        if len(required) != len(set(required)):
            _schema_definition_failure(location, "required contains duplicate property names")
    if "properties" in schema:
        properties = schema["properties"]
        if not isinstance(properties, dict):
            _schema_definition_failure(location, "properties must be an object")
        for name, child in properties.items():
            if not isinstance(name, str):
                _schema_definition_failure(location, "property names must be strings")
            _assert_supported_schema(child, root, f"{location}.properties[{name!r}]", seen)
    if "$defs" in schema:
        definitions = schema["$defs"]
        if not isinstance(definitions, dict):
            _schema_definition_failure(location, "$defs must be an object")
        if seen is None:
            seen = set()
        if id(definitions) in seen:
            return
        seen.add(id(definitions))
        for name, child in definitions.items():
            if not isinstance(name, str):
                _schema_definition_failure(location, "$defs names must be strings")
            _assert_supported_schema(child, root, f"{location}.$defs[{name!r}]", seen)
    if "propertyNames" in schema:
        _assert_supported_schema(schema["propertyNames"], root, f"{location}.propertyNames", seen)
    if "items" in schema:
        _assert_supported_schema(schema["items"], root, f"{location}.items", seen)
    if "additionalProperties" in schema:
        additional = schema["additionalProperties"]
        if not isinstance(additional, bool):
            _assert_supported_schema(additional, root, f"{location}.additionalProperties", seen)
    if "$ref" in schema:
        _resolve_schema_reference(root, schema["$ref"])
    if "enum" in schema and not isinstance(schema["enum"], list):
        _schema_definition_failure(location, "enum must be an array")
    if "pattern" in schema:
        pattern = schema["pattern"]
        if not isinstance(pattern, str):
            _schema_definition_failure(location, "pattern must be a string")
        try:
            re.compile(pattern)
        except re.error as exc:
            _schema_definition_failure(location, f"invalid regular expression: {exc}")
    for key in ("minLength", "maxLength"):
        value = schema.get(key)
        if key in schema and (isinstance(value, bool) or not isinstance(value, int) or value < 0):
            _schema_definition_failure(location, f"{key} must be a non-negative integer")
    for key in ("minimum", "maximum"):
        value = schema.get(key)
        if key in schema and not _finite_number(value):
            _schema_definition_failure(location, f"{key} must be a finite number")


def _finite_number(value: object) -> bool:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return False
    return isinstance(value, int) or math.isfinite(value)


def _json_values_equal(left: object, right: object) -> bool:
    if isinstance(left, bool) or isinstance(right, bool):
        return type(left) is type(right) and left == right
    if isinstance(left, (int, float)) and isinstance(right, (int, float)):
        return _finite_number(left) and _finite_number(right) and left == right
    if type(left) is not type(right):
        return False
    if isinstance(left, dict):
        return left.keys() == right.keys() and all(_json_values_equal(left[key], right[key]) for key in left)
    if isinstance(left, list):
        return len(left) == len(right) and all(_json_values_equal(a, b) for a, b in zip(left, right))
    return left == right


def _matches_schema_type(value: object, type_name: str) -> bool:
    if type_name == "null":
        return value is None
    if type_name == "boolean":
        return isinstance(value, bool)
    if type_name == "object":
        return isinstance(value, dict)
    if type_name == "array":
        return isinstance(value, list)
    if type_name == "string":
        return isinstance(value, str)
    if type_name == "number":
        return _finite_number(value)
    if type_name == "integer":
        return (isinstance(value, int) and not isinstance(value, bool)) or (
            isinstance(value, float) and math.isfinite(value) and value.is_integer()
        )
    return False


def _validate_schema_value(
    value: object,
    schema: object,
    root: dict[str, object],
    path: tuple[str | int, ...] = (),
) -> None:
    if isinstance(schema, bool):
        if not schema:
            _schema_failure(path, "value is rejected by the schema")
        return
    if not isinstance(schema, dict):
        _schema_definition_failure("$", "schema must be an object or boolean")
    if "$ref" in schema:
        _validate_schema_value(value, _resolve_schema_reference(root, schema["$ref"]), root, path)

    if "type" in schema:
        type_spec = schema["type"]
        type_names = [type_spec] if isinstance(type_spec, str) else type_spec
        if not any(_matches_schema_type(value, type_name) for type_name in type_names):
            _schema_failure(path, f"expected type {type_spec!r}")
    if "const" in schema and not _json_values_equal(value, schema["const"]):
        _schema_failure(path, f"must equal {schema['const']!r}")
    if "enum" in schema and not any(_json_values_equal(value, item) for item in schema["enum"]):
        _schema_failure(path, f"must be one of {schema['enum']!r}")

    if isinstance(value, str):
        if "minLength" in schema and len(value) < schema["minLength"]:
            _schema_failure(path, f"must have at least {schema['minLength']} characters")
        if "maxLength" in schema and len(value) > schema["maxLength"]:
            _schema_failure(path, f"must have at most {schema['maxLength']} characters")
        if "pattern" in schema and re.search(schema["pattern"], value) is None:
            _schema_failure(path, f"must match {schema['pattern']!r}")
    if _finite_number(value):
        if "minimum" in schema and value < schema["minimum"]:
            _schema_failure(path, f"must be at least {schema['minimum']}")
        if "maximum" in schema and value > schema["maximum"]:
            _schema_failure(path, f"must be at most {schema['maximum']}")

    if isinstance(value, dict):
        required = schema.get("required", [])
        for name in required:
            if name not in value:
                _schema_failure(path + (name,), "is required")
        property_names = schema.get("propertyNames")
        if property_names is not None:
            for name in value:
                _validate_schema_value(name, property_names, root, path + (name,))
        properties = schema.get("properties", {})
        if isinstance(properties, dict):
            for name, child in properties.items():
                if name in value:
                    _validate_schema_value(value[name], child, root, path + (name,))
        additional = schema.get("additionalProperties", True)
        if additional is False:
            known = set(properties) if isinstance(properties, dict) else set()
            unknown = [name for name in value if name not in known]
            if unknown:
                _schema_failure(path + (unknown[0],), "unknown property")
        elif isinstance(additional, (dict, bool)) and additional is not True:
            known = set(properties) if isinstance(properties, dict) else set()
            for name, item in value.items():
                if name not in known:
                    _validate_schema_value(item, additional, root, path + (name,))
    if isinstance(value, list) and "items" in schema:
        for index, item in enumerate(value):
            _validate_schema_value(item, schema["items"], root, path + (index,))


def _metadata_without_duplicate_keys(value: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, item in value:
        if key in result:
            raise ValueError(f"duplicate schema key: {key}")
        result[key] = item
    return result


def _reject_json_constant(token: str) -> None:
    raise ValueError(f"invalid JSON constant: {token}")


def _load_schema(schema_path: Path) -> dict[str, object]:
    try:
        schema = json.loads(
            schema_path.read_text(encoding="utf-8"),
            object_pairs_hook=_metadata_without_duplicate_keys,
            parse_constant=_reject_json_constant,
        )
    except (OSError, UnicodeDecodeError, TypeError, ValueError, json.JSONDecodeError) as exc:
        raise SchemaValidationError(f"schema is not valid UTF-8 JSON: {schema_path}") from exc
    if not isinstance(schema, dict):
        raise SchemaValidationError(f"schema must be a JSON object: {schema_path}")
    _assert_supported_schema(schema, schema)
    return schema


def validate_metadata(metadata: dict[str, object], schema_path: Path) -> None:
    """Validate metadata against one schema using only the standard library."""

    schema = _load_schema(schema_path)
    _validate_schema_value(metadata, schema, schema)

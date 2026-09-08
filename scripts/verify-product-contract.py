#!/usr/bin/env python3
"""Validate a const-only product identity contract without dependencies."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys


def validate(document: object, schema: object, location: str = "") -> list[str]:
    if not isinstance(schema, dict):
        return [f"invalid schema at {location or '<root>'}"]
    if schema.get("type") == "object":
        if not isinstance(document, dict):
            return [f"{location or '<root>'} must be an object"]
        properties = schema.get("properties")
        required = schema.get("required")
        if not isinstance(properties, dict) or not isinstance(required, list):
            return [f"invalid object schema at {location or '<root>'}"]
        errors: list[str] = []
        for field in required:
            child = f"{location}.{field}" if location else field
            if field not in document:
                errors.append(f"missing required field {child}")
        if schema.get("additionalProperties") is False:
            for field in document.keys() - properties.keys():
                child = f"{location}.{field}" if location else field
                errors.append(f"unreviewed field {child}")
        for field in document.keys() & properties.keys():
            child = f"{location}.{field}" if location else field
            errors.extend(validate(document[field], properties[field], child))
        return errors
    if "const" in schema and document != schema["const"]:
        return [f"{location} must equal the approved value"]
    return []


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser()
    parser.add_argument("--contract", type=Path, default=root / "config/product-identity.json")
    parser.add_argument("--schema", type=Path, default=root / "config/product-identity.schema.json")
    args = parser.parse_args()
    try:
        document = json.loads(args.contract.read_text())
        schema = json.loads(args.schema.read_text())
    except (OSError, json.JSONDecodeError) as error:
        print(f"product-contract: {error}", file=sys.stderr)
        return 2
    errors = validate(document, schema)
    if errors:
        for error in errors:
            print(f"product-contract: {error}", file=sys.stderr)
        return 1
    print("product identity contract verification passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

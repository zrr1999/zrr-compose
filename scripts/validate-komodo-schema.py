#!/usr/bin/env python3
from __future__ import annotations

import json
import pathlib
import sys
import tomllib

from jsonschema import Draft7Validator


def main() -> int:
    if len(sys.argv) < 3:
        sys.stderr.write("usage: validate-komodo-schema.py SCHEMA RESOURCE...\n")
        return 2

    schema_path = pathlib.Path(sys.argv[1])
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    validator = Draft7Validator(schema)
    failed = False

    for raw_path in sys.argv[2:]:
        path = pathlib.Path(raw_path)
        with path.open("rb") as stream:
            resource = tomllib.load(stream)
        errors = sorted(validator.iter_errors(resource), key=lambda error: list(error.path))
        for error in errors:
            location = ".".join(str(part) for part in error.path) or "<root>"
            sys.stderr.write(f"{path}:{location}: {error.message}\n")
            failed = True

    if failed:
        return 1

    sys.stdout.write(f"Komodo resource schema: {len(sys.argv) - 2} files valid for v2.2.0\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

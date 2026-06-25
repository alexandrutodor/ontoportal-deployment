#!/usr/bin/env python3
"""Validate example YAML and JSON files.

Examples are not installed by CI, but they should remain syntactically valid so
copy/paste instructions do not rot.
"""
from __future__ import annotations

import json
from pathlib import Path

import yaml


class UniqueKeyLoader(yaml.SafeLoader):
    """YAML loader that rejects duplicate mapping keys in examples."""


def construct_unique_mapping(loader: UniqueKeyLoader, node: yaml.nodes.MappingNode, deep: bool = False) -> dict[object, object]:
    mapping: dict[object, object] = {}
    seen: set[object] = set()
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in seen:
            raise yaml.constructor.ConstructorError(
                "while constructing a mapping",
                node.start_mark,
                f"found duplicate key {key!r}",
                key_node.start_mark,
            )
        seen.add(key)
        mapping[key] = loader.construct_object(value_node, deep=deep)
    return mapping


UniqueKeyLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, construct_unique_mapping)

ROOT = Path(__file__).resolve().parents[1]
EXAMPLES = ROOT / "examples"


def validate_yaml(path: Path) -> None:
    with path.open("r", encoding="utf-8") as handle:
        docs = list(yaml.load_all(handle, Loader=UniqueKeyLoader))
    if not docs:
        raise SystemExit(f"{path}: expected at least one YAML document")
    for index, doc in enumerate(docs, start=1):
        if doc is None:
            continue
        if not isinstance(doc, dict):
            raise SystemExit(f"{path}: document {index} must be a YAML mapping")


def validate_json(path: Path) -> None:
    with path.open("r", encoding="utf-8") as handle:
        json.load(handle)


def main() -> None:
    if not EXAMPLES.exists():
        return
    for path in sorted(EXAMPLES.rglob("*")):
        if path.suffix in {".yaml", ".yml"}:
            validate_yaml(path)
        elif path.suffix == ".json":
            validate_json(path)
    print("example manifests validated")


if __name__ == "__main__":
    main()

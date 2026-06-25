#!/usr/bin/env python3
"""Parse repository YAML files with duplicate-key detection."""
from __future__ import annotations

import pathlib
import sys
from typing import Any

import yaml


class UniqueKeyLoader(yaml.SafeLoader):
    """YAML loader that rejects duplicate mapping keys."""


def construct_unique_mapping(loader: UniqueKeyLoader, node: yaml.nodes.MappingNode, deep: bool = False) -> dict[Any, Any]:
    mapping: dict[Any, Any] = {}
    seen: set[Any] = set()
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

ROOT = pathlib.Path(__file__).resolve().parents[1]
PATTERNS = [
    ".github/workflows/*.yml",
    ".github/workflows/*.yaml",
    "chart/ontoportal/*.yaml",
    "values/**/*.yaml",
    "environments/*.yaml",
]


def main() -> int:
    errors = 0
    paths: list[pathlib.Path] = []
    for pattern in PATTERNS:
        paths.extend(ROOT.glob(pattern))
    for path in sorted(set(paths)):
        try:
            yaml.load(path.read_text(encoding="utf-8"), Loader=UniqueKeyLoader)
        except Exception as exc:  # noqa: BLE001 - validator should report all parse failures uniformly
            print(f"{path.relative_to(ROOT)}: {exc}", file=sys.stderr)
            errors += 1
    if errors:
        return 1
    print("repository YAML parsed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

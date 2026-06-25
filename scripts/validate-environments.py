#!/usr/bin/env python3
"""Validate modular environment recipes and image-build values."""
from __future__ import annotations

import pathlib
import subprocess
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
VALID_RUNTIMES = {"kubernetes", "compose"}
VALID_PROVIDERS = {"generic", "k3s", "aws-eks", "azure-aks", "gcp-gke"}
VALID_PROFILES = {"ontoportal-clean", "agroportal-clean", "matportal"}


def load_yaml(path: pathlib.Path) -> dict[str, Any]:
    data = yaml.load(path.read_text(encoding="utf-8"), Loader=UniqueKeyLoader) or {}
    if not isinstance(data, dict):
        raise SystemExit(f"{path.relative_to(ROOT)} must contain a YAML mapping")
    return data


def ensure_file(path: str, source: pathlib.Path) -> pathlib.Path:
    p = pathlib.Path(path)
    resolved = p if p.is_absolute() else ROOT / p
    try:
        resolved.resolve().relative_to(ROOT)
    except ValueError as exc:
        raise SystemExit(f"{source.relative_to(ROOT)}: path must stay inside repository: {path}") from exc
    if not resolved.is_file():
        raise SystemExit(f"{source.relative_to(ROOT)}: referenced file does not exist: {path}")
    return resolved


def validate_environment(path: pathlib.Path) -> None:
    env = load_yaml(path)
    if env.get("kind") != "Environment":
        raise SystemExit(f"{path.relative_to(ROOT)}: kind must be Environment")
    name = str((env.get("metadata") or {}).get("name") or "")
    if not name:
        raise SystemExit(f"{path.relative_to(ROOT)}: metadata.name is required")
    spec = env.get("spec") or {}
    if not isinstance(spec, dict):
        raise SystemExit(f"{path.relative_to(ROOT)}: spec must be a mapping")
    runtime = str(spec.get("runtime") or "kubernetes")
    provider = str(spec.get("provider") or "generic")
    profile = str(spec.get("profile") or "ontoportal-clean")
    if runtime not in VALID_RUNTIMES:
        raise SystemExit(f"{path.relative_to(ROOT)}: spec.runtime must be one of {sorted(VALID_RUNTIMES)}")
    if provider not in VALID_PROVIDERS:
        raise SystemExit(f"{path.relative_to(ROOT)}: spec.provider must be one of {sorted(VALID_PROVIDERS)}")
    if profile not in VALID_PROFILES:
        raise SystemExit(f"{path.relative_to(ROOT)}: spec.profile must be one of {sorted(VALID_PROFILES)}")
    values_files = spec.get("valuesFiles") or []
    if not isinstance(values_files, list) or not values_files:
        raise SystemExit(f"{path.relative_to(ROOT)}: spec.valuesFiles must be a non-empty list")
    for item in values_files:
        ensure_file(str(item), path)
    image_files = spec.get("imageBuildValuesFiles") or []
    if not isinstance(image_files, list):
        raise SystemExit(f"{path.relative_to(ROOT)}: spec.imageBuildValuesFiles must be a list")
    for item in image_files:
        ensure_file(str(item), path)
    if runtime == "compose" and provider not in {"generic", "k3s"}:
        raise SystemExit(f"{path.relative_to(ROOT)}: compose runtime should use provider generic or k3s, not {provider}")

    subprocess.run(
        [sys.executable, str(ROOT / "scripts/render-environment.py"), str(path), "--output", str(ROOT / ".environment-validate" / name)],
        cwd=ROOT,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def validate_image_build_values(path: pathlib.Path) -> None:
    subprocess.run(
        [sys.executable, str(ROOT / "scripts/image-build-matrix.py"), "-f", str(path)],
        cwd=ROOT,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def main() -> int:
    for path in sorted((ROOT / "values/image-builds").glob("*.yaml")):
        validate_image_build_values(path)
    for path in sorted((ROOT / "environments").glob("*.yaml")):
        validate_environment(path)
    tmp = ROOT / ".environment-validate"
    if tmp.exists():
        import shutil

        shutil.rmtree(tmp)
    print("environment recipes validated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Render an integrated OntoPortal deployment environment plan.

Environment recipes live under environments/*.yaml. A recipe declares the target
runtime/provider, ordered Helm values overlays, optional image build values, and
Terraform/Compose output preferences. This script does not deploy anything; it
materializes a reproducible bundle under dist/environments/<name>/.
"""
from __future__ import annotations

import argparse
import copy
import json
import pathlib
from typing import Any, Mapping

import yaml

import importlib.util

ROOT = pathlib.Path(__file__).resolve().parents[1]
BASE_VALUES = ROOT / "chart/ontoportal/values.yaml"
DIST_ROOT = ROOT / "dist/environments"
GENERATED_OUTPUTS = {
    ".env.sample",
    "build-matrix.json",
    "docker-compose.yml",
    "image-values.yaml",
    "summary.json",
    "terraform.tfvars",
    "values-files.txt",
    "values.yaml",
}

render_compose_spec = importlib.util.spec_from_file_location("render_compose", ROOT / "scripts/render-compose.py")
if render_compose_spec is None or render_compose_spec.loader is None:  # pragma: no cover
    raise RuntimeError("could not load render-compose.py")
render_compose = importlib.util.module_from_spec(render_compose_spec)
render_compose_spec.loader.exec_module(render_compose)

image_matrix_spec = importlib.util.spec_from_file_location("image_build_matrix", ROOT / "scripts/image-build-matrix.py")
if image_matrix_spec is None or image_matrix_spec.loader is None:  # pragma: no cover
    raise RuntimeError("could not load image-build-matrix.py")
image_build_matrix = importlib.util.module_from_spec(image_matrix_spec)
image_matrix_spec.loader.exec_module(image_build_matrix)


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


def load_yaml(path: pathlib.Path) -> dict[str, Any]:
    data = yaml.load(path.read_text(encoding="utf-8"), Loader=UniqueKeyLoader) or {}
    if not isinstance(data, dict):
        raise TypeError(f"{path} must contain a YAML mapping")
    return data


def deep_merge(base: dict[str, Any], overlay: Mapping[str, Any]) -> dict[str, Any]:
    result = copy.deepcopy(base)
    for key, value in overlay.items():
        if isinstance(value, Mapping) and isinstance(result.get(key), Mapping):
            result[key] = deep_merge(dict(result[key]), value)
        else:
            result[key] = copy.deepcopy(value)
    return result


def repo_path(path: str | pathlib.Path) -> pathlib.Path:
    p = pathlib.Path(path)
    return p if p.is_absolute() else ROOT / p


def rel(path: pathlib.Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def split_image_ref(image: str, default_tag: str) -> tuple[str, str]:
    lower = image.lower()
    if "@sha256:" in lower:
        return image.split("@", 1)[0], default_tag
    slash = image.rfind("/")
    colon = image.rfind(":")
    if colon > slash:
        return image[:colon], image[colon + 1 :]
    return image, default_tag


def assert_tag_only_image_tag(image_tag: str) -> str:
    lower = image_tag.lower()
    if lower.startswith("sha256:") or "@sha256:" in lower:
        raise SystemExit(
            "--image-tag accepts immutable tags only; digest-style values are not supported in this pass. "
            "Pass a tag like `sha-1234` or `v1.2.3`, not `@sha256:...` or `sha256:...`."
        )
    return image_tag


def render_image_values(values: Mapping[str, Any], image_tag: str) -> dict[str, Any]:
    matrix = image_build_matrix.get_image_builds(values, force_push=None, platform_override="")
    overlay: dict[str, Any] = {"images": {}}
    for item in matrix:
        repository, tag = split_image_ref(str(item["image"]), image_tag)
        helm_image = str(item.get("helm_image") or item["name"])
        overlay["images"][helm_image] = {"repository": repository, "tag": tag, "pullPolicy": "IfNotPresent"}
    return overlay


def merge_files(files: list[pathlib.Path]) -> dict[str, Any]:
    values = load_yaml(BASE_VALUES)
    for path in files:
        values = deep_merge(values, load_yaml(repo_path(path)))
    return values


def parse_recipe(path: pathlib.Path) -> tuple[str, dict[str, Any]]:
    recipe = load_yaml(repo_path(path))
    spec = recipe.get("spec") or {}
    if not isinstance(spec, dict):
        raise SystemExit(f"{path}: spec must be a mapping")
    name = str((recipe.get("metadata") or {}).get("name") or pathlib.Path(path).stem)
    if not name:
        raise SystemExit(f"{path}: metadata.name is required")
    return name, spec


def terraform_tfvars(name: str, spec: Mapping[str, Any], value_files: list[pathlib.Path], image_values_path: pathlib.Path | None) -> str:
    tf = dict(spec.get("terraform") or {})
    profile = str(spec.get("profile") or "ontoportal-clean")
    release_name = str(tf.get("release_name") or name)
    namespace = str(tf.get("namespace") or name)
    create_namespace = bool(tf.get("create_namespace", True))
    additional = [str(p) for p in value_files[1:]] if value_files else []
    if image_values_path is not None:
        additional.append(rel(image_values_path))
    variables = {
        "profile": profile,
        "release_name": release_name,
        "namespace": namespace,
        "create_namespace": create_namespace,
        "additional_values_files": additional,
    }
    for key in [
        "kubeconfig_path",
        "kube_context",
        "enable_keda",
        "enable_vpa",
        "enable_monitoring",
        "enable_loki",
        "enable_grafana_alloy",
        "enable_cert_manager",
        "enable_external_secrets",
        "enable_kyverno",
        "enable_velero",
        "velero_values_file",
    ]:
        if key in tf:
            variables[key] = tf[key]

    lines: list[str] = [f"# Generated by scripts/render-environment.py for {name}"]
    for key, value in variables.items():
        if isinstance(value, bool):
            lines.append(f"{key} = {str(value).lower()}")
        elif isinstance(value, list):
            lines.append(f"{key} = [")
            for item in value:
                lines.append(f"  {json.dumps(str(item))},")
            lines.append("]")
        else:
            lines.append(f"{key} = {json.dumps(str(value))}")
    lines.append("")
    return "\n".join(lines)


def render(recipe_path: pathlib.Path, image_tag: str, output: pathlib.Path | None = None) -> pathlib.Path:
    name, spec = parse_recipe(recipe_path)
    spec_images = spec.get("images") or {}
    if image_tag == "replace-with-built-tag" and isinstance(spec_images, Mapping) and spec_images.get("tag"):
        image_tag = str(spec_images["tag"])
    assert_tag_only_image_tag(image_tag)
    value_files = [pathlib.Path(str(p)) for p in spec.get("valuesFiles", [])]
    if not value_files:
        profile = str(spec.get("profile") or "ontoportal-clean")
        value_files = [pathlib.Path(f"values/profiles/{profile}.yaml")]
    image_value_files = [pathlib.Path(str(p)) for p in spec.get("imageBuildValuesFiles", [])]
    out_dir = output or DIST_ROOT / name
    out_dir.mkdir(parents=True, exist_ok=True)
    for generated_name in GENERATED_OUTPUTS:
        generated_path = out_dir / generated_name
        if generated_path.exists():
            generated_path.unlink()

    values_with_build_config = merge_files(value_files + image_value_files)
    image_overlay: dict[str, Any] = {}
    image_values_path: pathlib.Path | None = None
    if (values_with_build_config.get("imageBuilds") or {}).get("enabled"):
        image_overlay = render_image_values(values_with_build_config, image_tag)
        image_values_path = out_dir / "image-values.yaml"
        image_values_path.write_text(yaml.safe_dump(image_overlay, sort_keys=False), encoding="utf-8")

    merged_values = merge_files(value_files)
    if image_overlay:
        merged_values = deep_merge(merged_values, image_overlay)
    merged_values = deep_merge(
        merged_values,
        {
            "deploymentTarget": {
                "provider": spec.get("provider", merged_values.get("deploymentTarget", {}).get("provider", "generic")),
                "runtime": spec.get("runtime", merged_values.get("deploymentTarget", {}).get("runtime", "kubernetes")),
                "distribution": spec.get("distribution", merged_values.get("deploymentTarget", {}).get("distribution", merged_values.get("profile", {}).get("name", "ontoportal"))),
                "imageMode": "build" if image_overlay else merged_values.get("deploymentTarget", {}).get("imageMode", "existing"),
            }
        },
    )

    (out_dir / "values.yaml").write_text(yaml.safe_dump(merged_values, sort_keys=False), encoding="utf-8")
    (out_dir / "values-files.txt").write_text("\n".join(str(p) for p in value_files + image_value_files) + "\n", encoding="utf-8")
    (out_dir / "build-matrix.json").write_text(json.dumps({"include": image_build_matrix.get_image_builds(values_with_build_config)}, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    compose = spec.get("compose") or {}
    if spec.get("runtime") == "compose" or compose.get("enabled"):
        compose_values = deep_merge(merged_values, load_yaml(ROOT / "values/profiles/docker-compose.yaml"))
        (out_dir / "docker-compose.yml").write_text(yaml.safe_dump(render_compose.render(compose_values), sort_keys=False, default_flow_style=False), encoding="utf-8")
        (out_dir / ".env.sample").write_text(render_compose.env_sample(compose_values), encoding="utf-8")

    if spec.get("runtime", "kubernetes") == "kubernetes" or (spec.get("terraform") or {}).get("enabled"):
        (out_dir / "terraform.tfvars").write_text(terraform_tfvars(name, spec, value_files, image_values_path), encoding="utf-8")

    summary = {
        "name": name,
        "runtime": spec.get("runtime", "kubernetes"),
        "provider": spec.get("provider", "generic"),
        "valuesFiles": [str(p) for p in value_files],
        "imageBuildValuesFiles": [str(p) for p in image_value_files],
        "imageValuesFile": rel(image_values_path) if image_values_path else "",
        "imageTag": image_tag if image_values_path else "",
        "outputs": sorted(p.name for p in out_dir.iterdir()),
    }
    (out_dir / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"rendered {rel(out_dir)}")
    return out_dir


def main() -> int:
    parser = argparse.ArgumentParser(description="Render an integrated deployment environment bundle")
    parser.add_argument("environment", type=pathlib.Path, help="Environment recipe YAML")
    parser.add_argument("--image-tag", default="replace-with-built-tag", help="Immutable tag to use in generated image-values.yaml (digest values are rejected)")
    parser.add_argument("--output", type=pathlib.Path, help="Output directory; defaults to dist/environments/<name>")
    args = parser.parse_args()
    render(args.environment, args.image_tag, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

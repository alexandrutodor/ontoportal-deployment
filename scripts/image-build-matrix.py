#!/usr/bin/env python3
"""Create a Docker build matrix from OntoPortal imageBuilds values.

The matrix supports two source types:

* local: context/dockerfile live inside this deployment repository.
* git: source is fetched into .image-build-src/<component> before building.

This intentionally avoids cloning remote repositories during validation. The
workflow fetches the source in a separate step so the matrix generation remains
fast and safe in local checks.
"""
from __future__ import annotations

import argparse
import copy
import json
import os
import pathlib
import re
import sys
from typing import Any, Mapping
from urllib.parse import urlparse

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
BASE_VALUES = ROOT / "chart/ontoportal/values.yaml"
DEFAULT_TAGS = "type=ref,event=branch\ntype=ref,event=tag\ntype=sha,prefix=sha-"
COMPONENT_TO_HELM_IMAGE = {
    "api": "api",
    "cron": "cron",
    "ui": "ui",
    "mgrep": "mgrep",
    "virtuoso": "virtuoso",
    "fairness": "fairness",
    "assistant": "assistant",
    "ontopanel": "ontopanel",
}


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


def repo_path(value: str | os.PathLike[str]) -> pathlib.Path:
    path = pathlib.Path(value)
    return path if path.is_absolute() else ROOT / path


def read_values(paths: list[pathlib.Path]) -> dict[str, Any]:
    values = load_yaml(BASE_VALUES)
    for path in paths:
        values = deep_merge(values, load_yaml(repo_path(path)))
    return values


def read_environment(path: pathlib.Path) -> tuple[str, list[pathlib.Path], list[pathlib.Path], dict[str, Any]]:
    env = load_yaml(repo_path(path))
    spec = env.get("spec") or {}
    if not isinstance(spec, Mapping):
        raise SystemExit(f"{path}: spec must be a mapping")
    name = str((env.get("metadata") or {}).get("name") or pathlib.Path(path).stem)
    values_files = [pathlib.Path(str(p)) for p in spec.get("valuesFiles", [])]
    image_files = [pathlib.Path(str(p)) for p in spec.get("imageBuildValuesFiles", [])]
    return name, values_files, image_files, dict(spec)


def ensure_inside_repo(path: pathlib.Path, field: str, source: str) -> pathlib.Path:
    resolved = path.resolve()
    try:
        resolved.relative_to(ROOT)
    except ValueError as exc:
        raise SystemExit(f"{source}: {field} must stay inside the repository: {path}") from exc
    return resolved


def bool_value(value: Any, default: bool) -> bool:
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return value.lower() in {"1", "true", "yes", "on"}
    raise SystemExit(f"expected boolean value, got {value!r}")


def sanitize_name(name: str) -> str:
    safe = re.sub(r"[^a-zA-Z0-9_.-]+", "-", name).strip("-._")
    return safe or "image"


def git_host(url: str) -> str:
    parsed = urlparse(url)
    if parsed.scheme in {"https", "http", "ssh", "git+ssh"} and parsed.hostname:
        return parsed.hostname
    match = re.match(r"^(?:[^@/]+@)?([^:/]+):.+$", url)
    if match:
        return match.group(1)
    raise SystemExit(f"git source url must be http(s), ssh, or scp-like git syntax, got {url!r}")


def host_allowed(url: str, allowed_hosts: list[str], source: str) -> None:
    host = git_host(url)
    if host not in set(allowed_hosts):
        allowed = ", ".join(allowed_hosts)
        raise SystemExit(f"{source}: git source host {host!r} is not allowed; allowed hosts: {allowed}")


def image_prefix_allowed(image: str, prefixes: list[str], source: str) -> None:
    if not any(image.startswith(prefix) for prefix in prefixes):
        allowed = ", ".join(prefixes)
        raise SystemExit(f"{source}: image {image!r} must start with one of: {allowed}")


def image_list(value: Any) -> list[str]:
    if not value:
        return []
    if isinstance(value, str):
        parts = value.replace(",", "\n").splitlines()
    elif isinstance(value, list):
        parts = value
    else:
        raise SystemExit("publishImages must be a list or newline/comma-separated string")
    return [str(part).strip() for part in parts if str(part).strip()]


def unique(items: list[str]) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for item in items:
        if item not in seen:
            seen.add(item)
            result.append(item)
    return result


def get_image_builds(values: Mapping[str, Any], *, include_disabled: bool = False, force_push: bool | None = None, platform_override: str = "") -> list[dict[str, Any]]:
    cfg = values.get("imageBuilds") or {}
    if not isinstance(cfg, Mapping) or not cfg.get("enabled"):
        return []
    defaults = cfg.get("defaults") or {}
    if not isinstance(defaults, Mapping):
        raise SystemExit("imageBuilds.defaults must be a mapping")
    components = cfg.get("components") or {}
    if not isinstance(components, Mapping):
        raise SystemExit("imageBuilds.components must be a mapping")

    allowed_prefixes = [str(x) for x in defaults.get("allowedImagePrefixes", ["ghcr.io/", "docker.io/"])]
    allowed_hosts = [str(x) for x in defaults.get("allowedGitHosts", ["github.com"])]
    matrix: list[dict[str, Any]] = []

    for name, item in sorted(components.items()):
        if not isinstance(item, Mapping):
            raise SystemExit(f"imageBuilds.components.{name} must be a mapping")
        enabled = bool_value(item.get("enabled"), False)
        if not enabled and not include_disabled:
            continue
        image = str(item.get("image") or "").strip()
        if not image:
            raise SystemExit(f"imageBuilds.components.{name}.image is required when enabled")
        image_prefix_allowed(image, allowed_prefixes, f"imageBuilds.components.{name}")
        publish_images = unique([image] + image_list(item.get("publishImages")))
        for publish_image in publish_images:
            image_prefix_allowed(publish_image, allowed_prefixes, f"imageBuilds.components.{name}.publishImages")
        source = item.get("source") or {}
        if not isinstance(source, Mapping):
            raise SystemExit(f"imageBuilds.components.{name}.source must be a mapping")
        source_type = str(source.get("type") or "local")
        platforms = platform_override or str(item.get("platforms") or defaults.get("platforms") or "linux/amd64,linux/arm64")
        tags = str(item.get("tags") or defaults.get("tags") or DEFAULT_TAGS)
        push = bool_value(item.get("push"), bool_value(defaults.get("push"), True))
        if force_push is not None:
            push = force_push
        helm_image = str(item.get("helmImage") or COMPONENT_TO_HELM_IMAGE.get(str(name), str(name)))
        build_args = item.get("buildArgs") or {}
        if build_args and not isinstance(build_args, Mapping):
            raise SystemExit(f"imageBuilds.components.{name}.buildArgs must be a mapping")

        entry: dict[str, Any] = {
            "name": str(name),
            "image": image,
            "images": "\n".join(publish_images),
            "publish_images": publish_images,
            "uses_ghcr": any(img.startswith("ghcr.io/") for img in publish_images),
            "uses_dockerhub": any(img.startswith("docker.io/") for img in publish_images),
            "helm_image": helm_image,
            "platforms": platforms,
            "tags": tags,
            "push": push,
            "source_type": source_type,
            "build_args": {str(k): str(v) for k, v in dict(build_args).items()},
        }

        if source_type == "local":
            context = ensure_inside_repo(repo_path(str(source.get("context") or ".")), "context", f"imageBuilds.components.{name}")
            dockerfile = ensure_inside_repo(repo_path(str(source.get("dockerfile") or "Dockerfile")), "dockerfile", f"imageBuilds.components.{name}")
            if not context.exists():
                raise SystemExit(f"imageBuilds.components.{name}: local context does not exist: {context.relative_to(ROOT)}")
            if not dockerfile.is_file():
                raise SystemExit(f"imageBuilds.components.{name}: local dockerfile does not exist: {dockerfile.relative_to(ROOT)}")
            try:
                dockerfile.relative_to(context)
            except ValueError as exc:
                raise SystemExit(f"imageBuilds.components.{name}: dockerfile must be inside context") from exc
            if push and context == ROOT:
                raise SystemExit(f"imageBuilds.components.{name}: publishing from repository root is not allowed")
            entry.update({
                "context": str(context.relative_to(ROOT)),
                "dockerfile": str(dockerfile.relative_to(ROOT)),
                "git_url": "",
                "git_ref": "",
                "git_context": "",
                "git_dockerfile": "",
            })
        elif source_type == "git":
            url = str(source.get("url") or "").strip()
            if not url:
                raise SystemExit(f"imageBuilds.components.{name}.source.url is required for git sources")
            host_allowed(url, allowed_hosts, f"imageBuilds.components.{name}")
            ref = str(source.get("ref") or "main")
            git_context = str(source.get("context") or ".").strip().lstrip("/")
            git_dockerfile = str(source.get("dockerfile") or "Dockerfile").strip().lstrip("/")
            base = pathlib.Path(".image-build-src") / sanitize_name(str(name))
            context = base / git_context
            dockerfile = context / git_dockerfile
            entry.update({
                "context": str(context),
                "dockerfile": str(dockerfile),
                "git_url": url,
                "git_ref": ref,
                "git_context": git_context,
                "git_dockerfile": git_dockerfile,
            })
        else:
            raise SystemExit(f"imageBuilds.components.{name}.source.type must be local or git")
        matrix.append(entry)
    return matrix


def legacy_image_json_matrix(force_push: bool | None, platform_override: str) -> list[dict[str, Any]]:
    matrix: list[dict[str, Any]] = []
    for path in sorted((ROOT / "images").glob("*/image.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(data, dict) or not data.get("enabled", False):
            continue
        values = {
            "imageBuilds": {
                "enabled": True,
                "defaults": {
                    "allowedImagePrefixes": ["ghcr.io/matportal/", "docker.io/matportal/"],
                    "platforms": platform_override or data.get("platforms", "linux/amd64,linux/arm64"),
                    "tags": data.get("tags", DEFAULT_TAGS),
                    "push": data.get("push", True),
                },
                "components": {
                    path.parent.name: {
                        "enabled": True,
                        "image": data.get("image", ""),
                        "source": {
                            "type": "local",
                            "context": data.get("context") or str(path.parent.relative_to(ROOT)),
                            "dockerfile": data.get("dockerfile") or str(path.parent.relative_to(ROOT) / pathlib.Path("Dockerfile")),
                        },
                    }
                },
            }
        }
        matrix.extend(get_image_builds(values, force_push=force_push, platform_override=platform_override))
    return matrix


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate Docker build matrix from imageBuilds values")
    parser.add_argument("-f", "--values", action="append", default=[], type=pathlib.Path, help="Values YAML to merge. Repeatable.")
    parser.add_argument("--environment", type=pathlib.Path, help="Environment recipe whose values/imageBuildValuesFiles should be used")
    parser.add_argument("--include-legacy", action="store_true", help="Also include enabled images/*/image.json definitions")
    parser.add_argument("--force-push", choices=["true", "false"], help="Override push for all matrix entries")
    parser.add_argument("--platforms", default="", help="Override platforms for all matrix entries")
    parser.add_argument("--github-output", action="store_true", help="Write has_images and matrix to $GITHUB_OUTPUT")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    value_files = [pathlib.Path(p) for p in args.values]
    if args.environment:
        _, env_value_files, env_image_files, _ = read_environment(args.environment)
        value_files = env_value_files + env_image_files + value_files
    force_push = None if args.force_push is None else args.force_push == "true"
    matrix = get_image_builds(read_values(value_files), force_push=force_push, platform_override=args.platforms)
    if args.include_legacy:
        matrix.extend(legacy_image_json_matrix(force_push, args.platforms))

    output = {"include": matrix}
    if args.github_output:
        github_output = os.environ.get("GITHUB_OUTPUT")
        if not github_output:
            raise SystemExit("--github-output requires GITHUB_OUTPUT")
        with pathlib.Path(github_output).open("a", encoding="utf-8") as fh:
            fh.write(f"has_images={'true' if matrix else 'false'}\n")
            fh.write("matrix<<JSON\n")
            fh.write(json.dumps(output, sort_keys=True))
            fh.write("\nJSON\n")
    else:
        print(json.dumps(output, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

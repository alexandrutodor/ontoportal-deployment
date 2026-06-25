#!/usr/bin/env python3
"""Static production-readiness checks for OntoPortal deployment values.

This does not replace a live cluster test. It catches common mistakes before
someone promotes a profile into staging or production.
"""
from __future__ import annotations

import argparse
import copy
import pathlib
import sys
from typing import Any, Mapping

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
BASE = ROOT / "chart/ontoportal/values.yaml"
SCALABLE_COMPONENTS = ["api", "ui", "fairness", "assistant"]
RESOURCE_COMPONENTS = [
    "api",
    "cron",
    "ui",
    "redis",
    "solr",
    "mgrep",
    "store",
    "mysql",
    "memcached",
    "fairness",
    "matomo",
    "assistant",
    "ontopanel",
]
VPA_COMPONENTS = {
    "api": "api",
    "cron": "cron",
    "ui": "ui",
    "redis": "redis",
    "solr": "solr",
    "mgrep": "mgrep",
    "store": "store",
    "mysql": "mysql",
    "memcached": "memcached",
    "fairness": "fairness",
    "matomo": "matomo",
    "matomoDb": "matomo",
    "assistant": "assistant",
    "ontopanel": "ontopanel",
}
VALID_VPA_UPDATE_MODES = {"Off", "Initial", "Recreate", "InPlaceOrRecreate", "InPlace", "Auto"}
VALID_VPA_CONTROLLED_VALUES = {"RequestsOnly", "RequestsAndLimits"}


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


def get(mapping: Mapping[str, Any], path: str, default: Any = None) -> Any:
    cur: Any = mapping
    for part in path.split("."):
        if not isinstance(cur, Mapping) or part not in cur:
            return default
        cur = cur[part]
    return cur


def get_annotation(values: Mapping[str, Any], key: str) -> Any:
    annotations = get(values, "ingress.annotations", {}) or {}
    if not isinstance(annotations, Mapping):
        return None
    return annotations.get(key)


def merge_files(files: list[pathlib.Path]) -> dict[str, Any]:
    values = load_yaml(BASE)
    for path in files:
        p = path if path.is_absolute() else ROOT / path
        values = deep_merge(values, load_yaml(p))
    return values


def int_value(value: Any, default: int) -> int:
    if value in (None, ""):
        return default
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def bool_value(value: Any) -> bool:
    return value is True or (isinstance(value, str) and value.lower() in {"1", "true", "yes", "on"})


def hpa_uses_resource_metrics(values: Mapping[str, Any], name: str) -> bool:
    cfg = get(values, f"autoscaling.{name}", {}) or {}
    if not isinstance(cfg, Mapping) or not cfg.get("enabled"):
        return False
    return bool(cfg.get("targetCPUUtilizationPercentage") or cfg.get("targetMemoryUtilizationPercentage"))


def target_component_enabled(values: Mapping[str, Any], component: str) -> bool:
    if component == "store" and get(values, "store.engine") == "external":
        return False
    return bool(get(values, f"{component}.enabled", True))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("-f", "--values", action="append", default=[], help="values file, relative to repo root or absolute")
    parser.add_argument("--strict", action="store_true", help="treat warnings as errors")
    args = parser.parse_args()

    if not args.values:
        parser.error("provide at least one -f values file")

    values = merge_files([pathlib.Path(v) for v in args.values])
    warnings: list[str] = []
    errors: list[str] = []

    for name, cfg in sorted((values.get("images") or {}).items()):
        tag = str((cfg or {}).get("tag", ""))
        if tag in {"latest", "development", "main", "master", "edge", "nightly", "replace-with-built-tag"}:
            warnings.append(f"image {name!r} uses floating or placeholder tag {tag!r}; pin an immutable version or digest before production")

    provider = str(get(values, "deploymentTarget.provider", "generic") or "generic")
    image_mode = str(get(values, "deploymentTarget.imageMode", "existing") or "existing")
    if provider not in {"generic", "k3s", "aws-eks", "azure-aks", "gcp-gke"}:
        warnings.append(f"deploymentTarget.provider={provider!r} is not one of the documented providers; ensure storage/ingress semantics are reviewed")
    if image_mode == "build" and not get(values, "imageBuilds.enabled"):
        placeholder_images = [name for name, cfg in (values.get("images") or {}).items() if str((cfg or {}).get("tag", "")) == "replace-with-built-tag"]
        if placeholder_images:
            warnings.append("deploymentTarget.imageMode=build is set but imageBuilds.enabled is false and generated image tags were not supplied")

    if provider == "gcp-gke" and get(values, "ingress.enabled"):
        if get(values, "ingress.useClassNameField"):
            warnings.append("GKE built-in Ingress uses the kubernetes.io/ingress.class annotation; set ingress.useClassNameField=false unless using a different controller")
        if not get_annotation(values, "kubernetes.io/ingress.class"):
            warnings.append("GKE provider overlay should set ingress.annotations.kubernetes.io/ingress.class for the intended controller")
    if provider == "aws-eks" and get(values, "ingress.enabled"):
        if (get(values, "ingress.className") or get(values, "global.ingressClassName")) != "alb":
            warnings.append("AWS EKS overlay normally uses the AWS Load Balancer Controller ingress class 'alb'; verify your ingress controller")
        if not get_annotation(values, "alb.ingress.kubernetes.io/target-type"):
            warnings.append("AWS EKS ALB ingress usually needs alb.ingress.kubernetes.io/target-type; verify target registration mode")
    if provider == "azure-aks" and get(values, "ingress.enabled"):
        if get(values, "ingress.useClassNameField") and not get(values, "ingress.className"):
            warnings.append("Azure AKS ingress overlay has ingressClassName enabled without a class; use a class or annotation for the installed controller")
        if not get_annotation(values, "kubernetes.io/ingress.class") and not get(values, "ingress.className"):
            warnings.append("Azure AKS ingress should identify the installed controller through ingress.className or kubernetes.io/ingress.class")

    if get(values, "ingress.enabled") and not get(values, "ingress.tls.enabled"):
        warnings.append("ingress is enabled without TLS; enable TLS or terminate TLS at a documented upstream proxy")

    if get(values, "secrets.create") and not get(values, "secrets.existingSecret"):
        warnings.append("chart-managed generated secrets are acceptable for dev, but production should use existingSecret or External Secrets")

    for comp in RESOURCE_COMPONENTS:
        if get(values, f"{comp}.enabled", True) and not get(values, f"{comp}.resources"):
            warnings.append(f"component {comp!r} has no resource requests/limits")

    shared_modes = get(values, "persistence.shared.accessModes", []) or []
    if (get(values, "api.replicas", 1) > 1 or get(values, "ui.replicas", 1) > 1) and "ReadWriteMany" not in shared_modes:
        errors.append("api/ui replicas >1 require ReadWriteMany shared storage or a redesigned shared-data strategy")

    api_ui_hpa_enabled = False
    keda_enabled = False
    for name in SCALABLE_COMPONENTS:
        cfg = get(values, f"autoscaling.{name}", {}) or {}
        if not isinstance(cfg, Mapping) or not cfg.get("enabled"):
            continue

        if not get(values, f"{name}.enabled", False):
            errors.append(f"autoscaling for {name!r} is enabled but component {name!r} is disabled")

        mode = str(cfg.get("mode") or "hpa")
        if mode not in {"hpa", "keda"}:
            errors.append(f"autoscaling.{name}.mode must be hpa or keda")
            continue
        api_ui_hpa_enabled = api_ui_hpa_enabled or (mode == "hpa" and name in {"api", "ui"})
        keda_enabled = keda_enabled or mode == "keda"

        has_cpu = bool(cfg.get("targetCPUUtilizationPercentage"))
        has_memory = bool(cfg.get("targetMemoryUtilizationPercentage"))
        triggers = get(values, f"autoscaling.{name}.keda.triggers", []) or []
        if not isinstance(triggers, list):
            errors.append(f"autoscaling.{name}.keda.triggers must be a list")
            triggers = []

        if not has_cpu and not has_memory and (mode != "keda" or not triggers):
            errors.append(f"autoscaling for {name!r} is enabled but no CPU, memory, or KEDA trigger is configured")
        if has_cpu and not get(values, f"{name}.resources.requests.cpu"):
            errors.append(f"autoscaling for {name!r} uses CPU utilization but {name}.resources.requests.cpu is missing")
        if has_memory and not get(values, f"{name}.resources.requests.memory"):
            errors.append(f"autoscaling for {name!r} uses memory utilization but {name}.resources.requests.memory is missing")

        max_replicas = int_value(cfg.get("maxReplicas"), 1)
        min_replicas = int_value(cfg.get("minReplicas"), 1)
        if min_replicas > max_replicas:
            errors.append(f"autoscaling for {name!r} has minReplicas greater than maxReplicas")
        if name in {"api", "ui"} and max_replicas > 1 and "ReadWriteMany" not in shared_modes:
            errors.append(f"autoscaling for {name!r} maxReplicas >1 requires ReadWriteMany shared storage")
        if name in {"api", "ui"} and max_replicas > 1 and get(values, f"{name}.strategy.type") != "RollingUpdate":
            errors.append(f"autoscaling for {name!r} maxReplicas >1 requires {name}.strategy.type=RollingUpdate")
        if mode == "keda" and min_replicas == 0 and (has_cpu or has_memory) and not triggers:
            errors.append(f"KEDA autoscaling for {name!r} cannot scale to zero with CPU/memory-only triggers")

    if api_ui_hpa_enabled and "ReadWriteMany" not in shared_modes:
        errors.append("API/UI HPA is enabled but shared storage is not ReadWriteMany")

    if keda_enabled:
        warnings.append("KEDA ScaledObjects are enabled; ensure KEDA operator/CRDs are installed before applying the OntoPortal chart")

    vpa_enabled = False
    vpa_values = values.get("verticalPodAutoscaling") or {}
    if not isinstance(vpa_values, Mapping):
        errors.append("verticalPodAutoscaling must be a mapping")
        vpa_values = {}

    for name, target_component in VPA_COMPONENTS.items():
        cfg = vpa_values.get(name, {}) or {}
        if not isinstance(cfg, Mapping) or not cfg.get("enabled"):
            continue

        vpa_enabled = True
        if not target_component_enabled(values, target_component):
            warnings.append(f"vertical pod autoscaling for {name!r} is enabled but the target workload is disabled; no VPA resource will render")

        update_mode = str(cfg.get("updateMode") or "Off")
        if update_mode not in VALID_VPA_UPDATE_MODES:
            errors.append(f"verticalPodAutoscaling.{name}.updateMode must be one of: {', '.join(sorted(VALID_VPA_UPDATE_MODES))}")
        if update_mode == "Auto":
            warnings.append(f"verticalPodAutoscaling.{name}.updateMode=Auto is deprecated in recent VPA releases; prefer Recreate, Initial, InPlace, or InPlaceOrRecreate")
        if update_mode in {"InPlace", "InPlaceOrRecreate"}:
            warnings.append(f"verticalPodAutoscaling.{name}.updateMode={update_mode} requires VPA/controller support and the in-place resizing feature gates on the cluster")

        controlled_values = str(cfg.get("controlledValues") or "RequestsOnly")
        if controlled_values not in VALID_VPA_CONTROLLED_VALUES:
            errors.append(f"verticalPodAutoscaling.{name}.controlledValues must be RequestsOnly or RequestsAndLimits")
        if controlled_values == "RequestsAndLimits":
            warnings.append(f"verticalPodAutoscaling.{name} controls limits as well as requests; verify this cannot lower memory limits below safe runtime needs")

        controlled_resources = cfg.get("controlledResources", ["cpu", "memory"])
        if not isinstance(controlled_resources, list) or not controlled_resources:
            errors.append(f"verticalPodAutoscaling.{name}.controlledResources must be a non-empty list")

        container_policies = cfg.get("containerPolicies", []) or []
        if container_policies and not isinstance(container_policies, list):
            errors.append(f"verticalPodAutoscaling.{name}.containerPolicies must be a list")
        if update_mode != "Off" and not (cfg.get("minAllowed") and cfg.get("maxAllowed")) and not container_policies:
            warnings.append(f"verticalPodAutoscaling.{name} mutates pods without minAllowed/maxAllowed bounds")
        if name in SCALABLE_COMPONENTS and update_mode != "Off" and hpa_uses_resource_metrics(values, name):
            errors.append(f"verticalPodAutoscaling.{name}.updateMode={update_mode} conflicts with CPU/memory based HPA/KEDA for the same workload")
        if update_mode in {"Recreate", "Auto", "InPlaceOrRecreate"} and name in {"api", "ui", "fairness", "assistant", "matomo"}:
            replicas = int_value(get(values, f"{target_component}.replicas"), 1)
            if replicas < 2 and not bool_value(get(values, f"podDisruptionBudgets.{target_component}.enabled", False)):
                warnings.append(f"verticalPodAutoscaling.{name}.updateMode={update_mode} can evict singleton pods; test disruption and add a PDB/replica plan")

    if vpa_enabled:
        warnings.append("VerticalPodAutoscaler resources are enabled; install the autoscaling.k8s.io/v1 VPA CRD/controller before applying the OntoPortal chart")

    store_engine = str(get(values, "store.engine", "virtuoso")).lower()
    if store_engine not in {"virtuoso", "external"}:
        errors.append("store.engine must be 'virtuoso' or 'external'")
    if store_engine == "external" and (not get(values, "store.host") or not get(values, "store.port")):
        errors.append("store.engine=external requires store.host and store.port")

    image_builds = values.get("imageBuilds") or {}
    if isinstance(image_builds, Mapping) and image_builds.get("enabled"):
        components = image_builds.get("components") or {}
        enabled_components = [name for name, cfg in components.items() if isinstance(cfg, Mapping) and cfg.get("enabled")] if isinstance(components, Mapping) else []
        if not enabled_components:
            errors.append("imageBuilds.enabled=true but no imageBuilds.components entries are enabled")
        for name in enabled_components:
            cfg = components.get(name) or {}
            if not cfg.get("image"):
                errors.append(f"imageBuilds.components.{name}.image is required")
            source = cfg.get("source") or {}
            if source.get("type") == "git" and not source.get("url"):
                errors.append(f"imageBuilds.components.{name}.source.url is required for git builds")

    if get(values, "assistant.enabled") and not get(values, "assistant.openaiApiKeySecret.name"):
        warnings.append("assistant is enabled without assistant.openaiApiKeySecret.name; set the provider secret required by the assistant runtime")

    if get(values, "cron.starterOntology.fromApiKey"):
        warnings.append("cron.starterOntology.fromApiKey is deprecated and is not rendered; use cron.starterOntology.fromApiKeySecret")

    if not get(values, "persistence.enabled", True):
        warnings.append("persistence is disabled; chart will use emptyDir volumes and data will be lost when pods are replaced")

    if not get(values, "monitoring.serviceMonitor.enabled"):
        warnings.append("ServiceMonitor is disabled; production should expose metrics or document another monitoring path")

    if get(values, "networkPolicy.enabled") is False:
        warnings.append("NetworkPolicy is disabled; production should enable it if the cluster has a policy-capable CNI")

    for message in errors:
        print(f"ERROR: {message}", file=sys.stderr)
    for message in warnings:
        print(f"WARN: {message}", file=sys.stderr)

    if errors or (warnings and args.strict):
        return 1
    print("production readiness check completed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

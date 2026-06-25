# Autoscaling with HPA, KEDA, and VPA

The chart now separates horizontal scaling from vertical right-sizing:

- `autoscaling.<component>.mode: hpa` renders a Kubernetes `autoscaling/v2` HorizontalPodAutoscaler for `api`, `ui`, `fairness`, and `assistant`.
- `autoscaling.<component>.mode: keda` renders a KEDA `ScaledObject` for the same horizontally scalable workloads.
- `verticalPodAutoscaling.<component>` renders `autoscaling.k8s.io/v1` VerticalPodAutoscaler resources for API, cron, UI, Redis, Solr, mgrep, RDF store, MySQL, memcached, FAIRness, Matomo, assistant, and OntoPanel deployments when the matching workload is enabled.

The default profiles keep all autoscaling disabled. Enable autoscaling only after the storage, metrics, and rollout constraints below are satisfied.

## Runtime constraints

API and UI pods mount the shared `/data` volume. Scaling either workload beyond one replica requires one of these designs:

1. `persistence.shared.accessModes: ["ReadWriteMany"]` with a storage class that really supports multi-writer access, or
2. a site-specific redesign that externalizes mutable shared data.

CPU and memory based horizontal scaling requires resource requests on the scaled workload. The chart fails rendering HPA/KEDA CPU/memory triggers when requests are missing, and the production checker reports the same issue.

API/UI horizontal overlays set `api.strategy.type` and `ui.strategy.type` to `RollingUpdate` with `maxUnavailable: 0`. Do not use `Recreate` for API/UI when HPA/KEDA can run more than one replica, because upgrades would intentionally stop old pods before replacement pods are ready.

KEDA `ScaledObject` resources require the KEDA operator and CRDs to exist before the OntoPortal chart is applied. Terraform can install KEDA first with `enable_keda=true`.

VPA `VerticalPodAutoscaler` resources require the VPA CRD/controller to exist before the OntoPortal chart is applied. Terraform can install the Fairwinds VPA chart first with `enable_vpa=true`. The safe first VPA step is `updateMode: Off`, which records recommendations without mutating running pods.

Do not combine mutating VPA modes (`Initial`, `Recreate`, `InPlace`, `InPlaceOrRecreate`, or deprecated `Auto`) with CPU/memory based HPA/KEDA on the same workload. VPA changes resource requests while resource-utilization HPA/KEDA uses those requests as its denominator. Use VPA `Off` for recommendations while HPA/KEDA owns replica count, or make horizontal scaling depend on custom/external metrics.

## Native HPA overlay

The included overlay enables conservative native HPA scaling for API and UI:

```bash
helm upgrade --install ontoportal chart/ontoportal \
  --namespace ontoportal \
  -f values/profiles/ontoportal-clean.yaml \
  -f values/profiles/production-recommended.yaml \
  -f values/addons/hpa-autoscaling.yaml
```

The overlay:

- sets shared storage to `ReadWriteMany`;
- sets API/UI resource requests needed by CPU/memory HPA metrics;
- switches API/UI rollout strategy to `RollingUpdate`;
- enables API/UI PDBs;
- configures scale-up/scale-down behavior to avoid sudden replica churn.

## KEDA operator through Terraform

```hcl
enable_keda = true
```

Terraform installs the upstream `kedacore/keda` chart using `values/addons/keda-operator.yaml`. Override `keda_chart_version`, `keda_namespace`, or `keda_values_file` for site-specific requirements.

## OntoPortal KEDA overlay

The included overlay enables conservative KEDA scaling for API and UI:

```bash
helm upgrade --install ontoportal chart/ontoportal \
  --namespace ontoportal \
  -f values/profiles/ontoportal-clean.yaml \
  -f values/profiles/production-recommended.yaml \
  -f values/addons/keda-autoscaling.yaml
```

The overlay:

- switches API/UI autoscaling to `mode: keda`;
- sets resource requests needed by CPU/memory triggers;
- sets shared storage to `ReadWriteMany`;
- switches API/UI rollout strategy to `RollingUpdate`;
- adds weekday business-hour cron triggers to pre-warm API/UI replicas;
- enables PDBs for API/UI.

## VPA operator through Terraform

```hcl
enable_vpa = true
```

Terraform installs the Fairwinds `vpa` Helm chart using `values/addons/vpa-operator.yaml`. Override `vpa_chart_version`, `vpa_namespace`, or `vpa_values_file` for site-specific requirements. Install metrics-server separately if the cluster does not already provide the resource metrics API.

## Recommendation-only VPA overlay

Start with recommendation-only VPA resources:

```bash
helm upgrade --install ontoportal chart/ontoportal \
  --namespace ontoportal \
  -f values/profiles/ontoportal-clean.yaml \
  -f values/profiles/production-recommended.yaml \
  -f values/addons/vpa-recommendations.yaml
```

The overlay renders VPA objects with `updateMode: Off`, `controlledValues: RequestsOnly`, and conservative `minAllowed`/`maxAllowed` bounds. It enables VPA values for optional components too; if those components are disabled, no VPA object is rendered for them.

After collecting recommendations over representative traffic, either copy the recommended requests into site values or deliberately switch selected workloads to a mutating mode. Use mutating modes first on singleton worker/dependency workloads where restart behavior is acceptable, or on replicated stateless services with tested PDBs and rollouts.

## Native HPA inline example

```yaml
persistence:
  shared:
    accessModes: ["ReadWriteMany"]
api:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 1
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
autoscaling:
  api:
    enabled: true
    mode: hpa
    minReplicas: 2
    maxReplicas: 4
    targetCPUUtilizationPercentage: 70
```

## Mutating VPA inline example

Use this pattern only after VPA recommendations and restart behavior are understood. Do not combine it with CPU/memory HPA/KEDA for the same workload.

```yaml
verticalPodAutoscaling:
  cron:
    enabled: true
    updateMode: Initial
    minAllowed:
      cpu: 250m
      memory: 1Gi
    maxAllowed:
      cpu: "4"
      memory: 8Gi
```

## Live KEDA verification

After applying a KEDA-enabled release, run:

```bash
make keda-check NAMESPACE=ontoportal RELEASE=ontoportal
```

The check verifies that KEDA CRDs exist, that API/UI `ScaledObject` resources target the expected deployments, that trigger and replica bounds are populated, that the `Ready=True` condition appears, and that KEDA creates the expected generated HPA. Set `KEDA_COMPONENTS="api ui fairness assistant"` to check additional enabled workloads.

A manual GitHub Actions workflow, `.github/workflows/keda-k3s-smoke.yml`, installs KEDA into a disposable k3s cluster, deploys the clean profile with the KEDA overlay, runs the deep smoke test, and then runs the same KEDA resource check.

## Live VPA verification

After applying a VPA-enabled release, run:

```bash
make vpa-check NAMESPACE=ontoportal RELEASE=ontoportal
```

The default check verifies API, UI, and cron VPA resources. Use `VPA_COMPONENTS="api ui cron redis-persistent redis-goo-cache redis-http-cache solr-term solr-prop mgrep store mysql cache"` for the clean split-dependency profile. Set `VPA_REQUIRE_RECOMMENDATION=true` only when the cluster has enough metrics history to publish recommendations.

A manual GitHub Actions workflow, `.github/workflows/vpa-k3s-smoke.yml`, installs VPA into a disposable k3s cluster, deploys the clean profile with the VPA recommendation overlay, runs the deep smoke test, and then runs the same VPA resource check.

## KEDA Prometheus example

Use this only after Prometheus is installed and the queried metric is stable.

```yaml
autoscaling:
  api:
    enabled: true
    mode: keda
    minReplicas: 1
    maxReplicas: 6
    targetCPUUtilizationPercentage: null
    targetMemoryUtilizationPercentage: null
    keda:
      triggers:
        - type: prometheus
          metadata:
            serverAddress: http://kube-prometheus-stack-prometheus.monitoring:9090
            metricName: ontoportal_api_requests_per_second
            query: sum(rate(http_requests_total{job="ontoportal-api"}[2m]))
            threshold: "20"
```

## Validation commands

```bash
make validate
make validate-ui-tests
python3 scripts/production-readiness-check.py \
  -f values/profiles/ontoportal-clean.yaml \
  -f values/profiles/production-recommended.yaml \
  -f values/addons/hpa-autoscaling.yaml
python3 scripts/production-readiness-check.py \
  -f values/profiles/ontoportal-clean.yaml \
  -f values/profiles/production-recommended.yaml \
  -f values/addons/keda-autoscaling.yaml
python3 scripts/production-readiness-check.py \
  -f values/profiles/ontoportal-clean.yaml \
  -f values/profiles/production-recommended.yaml \
  -f values/addons/vpa-recommendations.yaml
helm template ontoportal-hpa chart/ontoportal \
  --namespace ontoportal \
  -f values/profiles/ontoportal-clean.yaml \
  -f values/profiles/production-recommended.yaml \
  -f values/addons/hpa-autoscaling.yaml >/tmp/ontoportal-hpa.yaml
helm template ontoportal-keda chart/ontoportal \
  --namespace ontoportal \
  -f values/profiles/ontoportal-clean.yaml \
  -f values/profiles/production-recommended.yaml \
  -f values/addons/keda-autoscaling.yaml >/tmp/ontoportal-keda.yaml
helm template ontoportal-vpa chart/ontoportal \
  --namespace ontoportal \
  -f values/profiles/ontoportal-clean.yaml \
  -f values/profiles/production-recommended.yaml \
  -f values/addons/vpa-recommendations.yaml >/tmp/ontoportal-vpa.yaml
```

Live validation should also include a load test, observation of `kubectl get hpa,scaledobject,vpa,pods`, VPA recommendation review over representative traffic, and a rollback test. Do not treat a successful render as proof that autoscaling is safe for production.

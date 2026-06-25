# Observability stack

## What is included

The repository treats observability as platform infrastructure, not part of the OntoPortal application chart.

Included optional pieces:

- kube-prometheus-stack for Prometheus, Grafana, Alertmanager, node-exporter, kube-state-metrics, CRDs, and dashboards.
- OntoPortal `ServiceMonitor` generation for application services.
- Loki for log storage/query.
- Grafana Alloy for Kubernetes pod-log collection and forwarding to Loki.
- Trivy Operator ServiceMonitor support.

## Metrics path

Install kube-prometheus-stack:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  -f values/addons/monitoring-kube-prometheus-stack.yaml
```

Install OntoPortal with ServiceMonitor enabled:

```bash
-f values/addons/monitoring-servicemonitor.yaml
```

Check discovery:

```bash
kubectl -n ontoportal get servicemonitor
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
```

Then verify that OntoPortal services appear in Prometheus targets. If they do not, check ServiceMonitor labels, namespace selectors, service port names, and whether the application exposes Prometheus metrics at the scraped path.

## Logs path with Loki and Grafana Alloy

For a local or low-volume k3s acceptance test:

```bash
helm repo add grafana-community https://grafana-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
kubectl create namespace observability || true

helm upgrade --install loki grafana-community/loki \
  --namespace observability \
  -f values/addons/loki-monolithic-dev.yaml

helm upgrade --install grafana-alloy grafana/alloy \
  --namespace observability \
  -f values/addons/grafana-alloy-loki.yaml
```

For production, replace `loki-monolithic-dev.yaml` with a site-specific Loki file that uses external object storage and a deployment mode appropriate for the expected log volume.

Check logs:

```bash
kubectl -n observability get pods
kubectl -n observability logs daemonset/grafana-alloy --tail=200
```

In Grafana, add a Loki data source pointing to the Loki gateway service in the observability namespace, then query by namespace and component labels, for example:

```logql
{namespace="ontoportal"}
{namespace="matportal", component="api"}
```

## Alerting starter pack

Start with platform alerts from kube-prometheus-stack, then add application-specific alerts. A starter `PrometheusRule` is included at `examples/observability/prometheusrule-ontoportal-starter.yaml`.

Review namespace, release-prefix, labels, thresholds, and Alertmanager routing before applying it:

```bash
kubectl apply -f examples/observability/prometheusrule-ontoportal-starter.yaml
kubectl -n ontoportal get prometheusrule ontoportal-starter-alerts
```

The starter covers:

- no available replicas for API/UI/cron/dependencies/add-ons;
- pod restart bursts;
- cron worker unavailable;
- PVC free space below warning/critical thresholds;
- backup/Restic/Velero/VolSync-style Kubernetes Job failures.

Add site-specific alerts for high ingress 5xx rate, Trivy critical vulnerability reports in production namespaces, Solr JVM/heap once exposed, RDF-store health once metrics exist, and ontology import/processing SLIs after application metrics are available.

## Dashboard starter pack

Import `examples/observability/grafana-dashboard-ontoportal-overview.json` into Grafana as a first-pass operational dashboard.

It includes variables for Prometheus datasource, namespace, and Helm release, with panels for:

- namespace workload health,
- pod restarts and readiness,
- CPU/memory by pod,
- PVC usage,
- non-running pod phases.

Extend it with ingress request rate/errors/latency, Solr health and JVM metrics, RDF store health, ontology import and processing duration, and Loki log panels once those data sources exist.

## Known limitation

The chart creates the Kubernetes plumbing for metrics/logging, but the actual OntoPortal images may not expose rich Prometheus metrics. Future maintainers should add application instrumentation or sidecar/exporter support only after testing the real images.

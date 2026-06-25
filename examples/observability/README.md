# Observability starter pack

This directory contains application-level alert and dashboard starters for OntoPortal/MatPortal on k3s.

They assume kube-prometheus-stack is installed and collecting kube-state-metrics, kubelet/cAdvisor, and PVC metrics. The default examples target namespace/release `ontoportal`; copy and edit them for `matportal` or a site-specific release.

## Prerequisites

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  -f values/addons/monitoring-kube-prometheus-stack.yaml
```

If OntoPortal itself should expose `ServiceMonitor` objects, install the chart with:

```bash
-f values/addons/monitoring-servicemonitor.yaml
```

## Alert rules

Review and adjust `examples/observability/prometheusrule-ontoportal-starter.yaml` before applying:

- `metadata.namespace`: application namespace, usually `ontoportal` or `matportal`.
- `metadata.labels.release`: must match the kube-prometheus-stack release selector.
- PromQL namespace/release filters: replace `namespace="ontoportal"` and `ontoportal-.*` when the release differs.
- thresholds and severities: tune for your SLOs.

Apply:

```bash
kubectl apply -f examples/observability/prometheusrule-ontoportal-starter.yaml
kubectl -n ontoportal get prometheusrule ontoportal-starter-alerts
```

Starter alerts cover:

- no available replicas for API/UI/cron/dependencies/add-ons;
- pod restart bursts;
- cron deployment unavailable;
- PVC free space below 15% warning and 5% critical;
- backup/Restic/Velero/VolSync-style Kubernetes Job failures.

These alerts depend on platform metrics, not on OntoPortal application metrics. Add application-specific alerts for ontology import, annotator latency, search quality, and admin flows after those metrics exist.

## Grafana dashboard

Import `examples/observability/grafana-dashboard-ontoportal-overview.json` through Grafana's dashboard import UI.

The dashboard includes variables for:

- Prometheus datasource;
- namespace;
- Helm release (`ontoportal` or `matportal`).

Panels cover:

- available replicas by deployment;
- pod restart bursts;
- PVC used percent;
- memory working set;
- CPU cores;
- non-running pod phases.

For logs, install Loki/Alloy from `docs/observability.md` and add panels using queries such as:

```logql
{namespace="ontoportal"}
{namespace="matportal", component="api"}
```

## Production checklist

- Route critical alerts to Alertmanager receivers that are tested out of hours.
- Add runbook URLs to alert annotations after site runbooks are finalized.
- Verify PVC and kubelet metrics exist on the target k3s distribution.
- Create a backup freshness metric or heartbeat if backup Jobs do not follow predictable names.
- Keep dashboards versioned here, then import/provision them through Grafana for each environment.

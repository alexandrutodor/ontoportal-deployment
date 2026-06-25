# Observability troubleshooting

## ServiceMonitor exists but target is missing

Check labels:

```bash
kubectl -n ontoportal get servicemonitor -o yaml
kubectl -n ontoportal get svc --show-labels
```

Common causes:

- ServiceMonitor label does not match the Prometheus selector.
- Service port is not named `http`.
- ServiceMonitor is in a namespace Prometheus does not watch.
- The app does not expose metrics at the default path.

## Loki receives no logs

Check Alloy:

```bash
kubectl -n observability get pods
kubectl -n observability logs daemonset/grafana-alloy --tail=200
```

Check that the Loki gateway DNS in `values/addons/grafana-alloy-loki.yaml` matches the release and namespace.

## Grafana cannot query Loki

Port-forward Grafana and test the data source URL. For in-cluster Grafana, the usual URL is:

```text
http://loki-gateway.observability.svc.cluster.local
```

For a different release name or namespace, update the URL.

## Too many Loki labels

Keep labels low-cardinality. Do not label log streams by request ID, user ID, ontology ID, or arbitrary path. Prefer namespace, pod, container, component, release, and environment.

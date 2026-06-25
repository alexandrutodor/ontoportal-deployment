# High-availability deployment guide

This chart can be used as part of a high-availability OntoPortal or MatPortal deployment, but HA is not achieved by setting every replica count to `3`. The default profiles include single-instance stateful dependencies and `ReadWriteOnce` PVCs. Treat HA as an architecture with separate control-plane, ingress, storage, database, search, RDF store, backup, and application layers.

## HA readiness summary

| Layer | Default baseline | HA recommendation |
| --- | --- | --- |
| k3s control plane | single-node tutorial uses one server | 3 k3s server nodes with embedded etcd or external datastore |
| Ingress | Traefik on k3s | HA Traefik/nginx plus stable VIP/load balancer |
| Shared files | RWO PVCs | RWX storage or object/externalized shared data |
| MySQL | single chart-managed deployment | managed MySQL/MariaDB or operator-managed HA database |
| Redis | single/split deployments | managed Redis, Redis Sentinel, or operator-managed Redis |
| Solr | single or split cores | SolrCloud or externally managed Solr with tested configsets |
| RDF store | Virtuoso single endpoint | externally managed supported RDF store, or validated Virtuoso backup/restore and performance |
| API/UI | one replica by default | scale only after storage and session/shared-state constraints are solved |
| Backups | docs and hooks | scheduled backups plus restore drills |

## 1. Cluster topology

Recommended minimum production topology:

- 3 k3s server nodes with embedded etcd.
- 2+ worker nodes for application pods.
- A stable Kubernetes API endpoint through a load balancer or VIP.
- A stable ingress endpoint through a load balancer, BGP/MetalLB, kube-vip, or cloud LB.
- Storage that survives node loss.

For k3s HA setup, follow upstream k3s HA documentation for embedded etcd and use a stable `--tls-san` endpoint. Validate etcd snapshots before deploying workloads.

## 2. Storage strategy

The default k3s `local-path` storage is not HA. It binds data to one node and makes pod rescheduling across nodes unsafe.

Production options:

1. **RWX shared storage**: NFS, CephFS/Rook, Longhorn RWX, NetApp, EFS, or another CSI driver that supports the needed access modes.
2. **Externalize state**: move database, Solr, RDF store, and object/file data to managed services or dedicated operator-managed clusters.
3. **Node-pinned non-HA stateful services**: acceptable only for staging or explicitly documented maintenance windows.

Before increasing API/UI replicas or enabling HPA/KEDA horizontal autoscaling, ensure shared data uses `ReadWriteMany` or is otherwise externalized:

```yaml
persistence:
  shared:
    storageClassName: replace-with-rwx-storage-class
    accessModes: ["ReadWriteMany"]
```

## 3. Stateful dependencies

The external-service examples below describe the intended HA direction. Before using them in production, validate the exact environment variables required by the chosen OntoPortal/MatPortal images and add first-class chart values where duplicate `extraEnv` overrides would be too fragile.

### MySQL

The chart-managed MySQL is useful for development and staging. For HA, prefer a managed database, MariaDB Galera, MySQL InnoDB Cluster, or an operator-managed database. Point the UI/API to that database through site-specific values once the chart supports the exact external DB contract you need.

### Redis

Use managed Redis or an operator-managed Redis/Sentinel setup for production HA. The chart's `redis.mode=split` improves role separation, not availability.

### Solr

The chart supports single or split Solr services, but not full SolrCloud orchestration. For HA search:

- use externally managed SolrCloud;
- version and test OntoPortal configsets;
- test core/collection creation and restore procedures;
- keep the chart values pointing to stable Solr endpoints.

### RDF store

Virtuoso is the supported bundled RDF store. For HA, use an externally managed RDF store with documented backup/restore and performance characteristics, or validate Virtuoso clustering/backup mode independently.

## 4. Application scaling rules

Do not scale API/UI just to satisfy an HA checklist. First verify:

- all mounted shared paths are RWX or no longer shared through PVCs;
- sessions/cookies work across replicas;
- background jobs are singleton-safe;
- ontology import/index operations are not duplicated;
- readiness/liveness probes reflect real app health;
- resource requests/limits are set.

Then use site values such as:

```yaml
api:
  replicas: 2
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 1
ui:
  replicas: 2
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 1
persistence:
  shared:
    accessModes: ["ReadWriteMany"]
autoscaling:
  api:
    enabled: true
    mode: hpa
    minReplicas: 2
    maxReplicas: 4
  ui:
    enabled: true
    mode: hpa
    minReplicas: 2
    maxReplicas: 4
podDisruptionBudgets:
  api:
    enabled: true
    minAvailable: 1
  ui:
    enabled: true
    minAvailable: 1
```

If a release still uses RWO `local-path`, keep API/UI replicas at `1` and leave HPA/KEDA disabled. Use VPA in `updateMode: Off` first for resource recommendations; mutating VPA modes can evict or resize pods and must be tested against PDB/rollout behavior. For autoscaling guardrails, see `docs/autoscaling-keda.md`.

## 5. Ingress, TLS, and DNS

Production ingress should have:

- stable DNS for UI and API hosts;
- TLS through cert-manager or a managed certificate flow;
- explicit HTTP->HTTPS policy;
- request size/timeouts tuned for ontology uploads/imports;
- access logs and error logs collected centrally.

Install cert-manager and create an Issuer/ClusterIssuer before relying on TLS automation.

## 6. Observability and rollout controls

Install platform add-ons before enabling chart overlays that depend on CRDs:

```bash
# Verify ServiceMonitor CRDs exist before enabling monitoring.serviceMonitor.enabled
kubectl api-resources | grep -i '^servicemonitors'
```

Use:

- Prometheus/Grafana/Alertmanager for metrics and alerts;
- Loki/Alloy or equivalent for pod logs;
- Trivy Operator or equivalent for image/config scanning;
- NetworkPolicy only after testing ingress and dependency reachability;
- PDBs only after multiple healthy replicas exist.

## 7. HA deployment sequence

1. Build the HA k3s cluster and verify node failure behavior.
2. Install storage, ingress, cert-manager, monitoring, logging, and backup platform components.
3. Create external or operator-managed stateful services.
4. Create namespaces and synchronize secrets through an approved secret manager.
5. Render Helm with the production profile and site values.
6. Install with one API/UI replica first.
7. Run smoke, ontology import/search, Solr, RDF store, cron, UI login, and admin tests.
8. Enable PDBs and HPA/KEDA only after RWX/external state is proven; enable mutating VPA only after recommendation-only VPA has been observed under representative traffic.
9. Test pod eviction, node drain, backup, restore, rollback, and disaster recovery.

## 8. HA validation checklist

Before declaring the deployment HA, prove the following with commands and notes:

- One worker node can be drained without user-visible downtime.
- One API pod can be killed and traffic continues.
- One UI pod can be killed and sessions still work.
- Database failover is tested.
- Redis failover is tested.
- Solr/RDF-store failover or restore is tested.
- Ingress/LB failover is tested.
- A full namespace restore into a new namespace works.
- A full cluster-loss restore runbook exists and has been rehearsed.
- Alerts fire for pod crashloops, PVC capacity, failed backups, failed cron jobs, and API/UI unavailability.

## 9. What still needs engineering for stronger HA

The current chart would benefit from these future additions:

- documented external DB/Redis/Solr/RDF values contracts;
- optional SolrCloud profile or explicit external Solr profile;
- backup/restore automation tests in CI against a disposable k3s cluster;
- application-specific health checks beyond API `/` and UI `/`;
- ontology import/search/annotator smoke scripts;
- chart tests that assert PDB/HPA/KEDA/VPA/RWX constraints.

# Restic backup and restore strategy

Backups are only useful after a restore drill succeeds. This guide describes practical Restic strategies for single-node k3s, small servers, and HA clusters.

## 0. Backup scope

Back up all data needed to rebuild the service:

- Kubernetes manifests and Helm values used for the release.
- Kubernetes Secrets through an approved secret-management backup path.
- PVC data for API/UI shared files, Solr, RDF store, MySQL, Matomo, and other enabled components.
- k3s etcd snapshots for HA control-plane recovery.
- External database/search/RDF backups if those services are not chart-managed.

Do not rely on one backup method for every layer. Combine cluster-state backups, PVC backups, and application-native database/search dumps where possible.

## 1. Restic repository options

Common repository targets:

```bash
# S3-compatible object storage
export RESTIC_REPOSITORY=s3:https://s3.example.org/ontoportal-restic
export AWS_ACCESS_KEY_ID=<replace-with-access-key>
export AWS_SECRET_ACCESS_KEY=<replace-with-secret-key>

# SSH/SFTP target
export RESTIC_REPOSITORY=sftp:backup@example.org:/srv/restic/ontoportal

# Local USB/disk target for an offline small-server copy
export RESTIC_REPOSITORY=/mnt/backup/ontoportal-restic
```

Store `RESTIC_PASSWORD` in a root-only file, a password manager, Kubernetes Secret, or external secret manager. Do not commit it.

Initialize once:

```bash
restic snapshots || restic init
```

## 2. Strategy A: single-node k3s local-path host backup

This is the simplest strategy for a laptop or small server. It works because k3s `local-path` PVC data is stored on the node filesystem.

### 2.1 Quiesce the release

For the most consistent file-level backup, pause workloads before backing up PVCs:

```bash
NS=ontoportal
RELEASE=ontoportal
REPLICAS_FILE=/tmp/${RELEASE}-replicas.$(date +%s).txt
kubectl -n "$NS" get deploy -l app.kubernetes.io/instance="$RELEASE" \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.replicas}{"\n"}{end}' > "$REPLICAS_FILE"
kubectl -n "$NS" scale deploy -l app.kubernetes.io/instance="$RELEASE" --replicas=0
kubectl -n "$NS" wait --for=delete pod -l app.kubernetes.io/instance="$RELEASE" --timeout=10m || true
```

For production, prefer application-native dumps for MySQL/Solr/RDF store before scaling down or snapshotting.

### 2.2 Find PVC host paths

```bash
NS=ontoportal
kubectl -n "$NS" get pvc

RELEASE=ontoportal
PVC=${RELEASE}-shared-data
PV=$(kubectl -n "$NS" get pvc "$PVC" -o jsonpath='{.spec.volumeName}')
kubectl get pv "$PV" -o yaml | sed -n '/ local:/,/persistentVolumeReclaimPolicy/p;/ hostPath:/,/persistentVolumeReclaimPolicy/p'
```

On k3s local-path, the host path is usually under `/var/lib/rancher/k3s/storage/`. Confirm the exact path from the PV YAML before backing up or restoring.

### 2.3 Run Restic backup

```bash
sudo -E restic backup /var/lib/rancher/k3s/storage/<confirmed-pvc-path> \
  --tag namespace:$NS \
  --tag release:$RELEASE \
  --tag pvc:$PVC

sudo -E restic check --read-data-subset=1/20
```

Repeat for every PVC used by the release.

### 2.4 Resume workloads

```bash
while read -r name replicas; do
  kubectl -n "$NS" scale deploy "$name" --replicas="${replicas:-1}"
done < "$REPLICAS_FILE"
kubectl -n "$NS" get pods -w
SMOKE_DEEP=true scripts/smoke.sh "$NS" "$RELEASE"
```

## 3. Strategy B: VolSync Restic replication

For Kubernetes-native PVC backup, consider VolSync with its Restic mover. This is better than ad-hoc CronJobs because it manages PVC snapshots/replication patterns explicitly.

Use this when:

- your storage class supports snapshots or safe copy semantics;
- you want scheduled per-PVC backups;
- you can test restore into a new namespace.

High-level flow:

1. Install VolSync and required CRDs.
2. Create a Restic repository Secret.
3. Create one replication source per critical PVC.
4. Schedule backups.
5. Restore into a new PVC and namespace regularly.

Keep VolSync manifests in a site-specific private overlay until the exact PVC names and repository are finalized.

## 4. Strategy C: Velero filesystem backups

Velero with node-agent can back up Kubernetes objects plus filesystem data. Modern Velero may use Kopia by default; older setups used Restic. If explicit Restic is required, verify the Velero version and configuration before adopting it.

Use Velero when you need:

- namespace/object backup plus PVC data;
- scheduled cluster backups;
- restore into a new namespace;
- integration with object storage.

This repository includes a Velero provider values file, but provider credentials, plugins, schedules, retention, and restore procedures are site-specific.

## 5. Application-native dumps

File-level backups are not always enough for databases and search indexes. Add application-native dumps where possible:

- MySQL/MariaDB: `mysqldump` or physical backups from your DB platform.
- Solr: collection/core backup APIs, or rebuild from source data if documented.
- RDF store: vendor-specific export/snapshot.
- k3s etcd: `k3s etcd-snapshot save` for HA/server recovery.

For chart-managed MySQL on a small k3s node, a simple dump before Restic backup is safer than only copying files:

```bash
NS=ontoportal
MYSQL_POD=$(kubectl -n "$NS" get pod -l app.kubernetes.io/component=mysql -o jsonpath='{.items[0].metadata.name}')
kubectl -n "$NS" exec "$MYSQL_POD" -- sh -c 'mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" --all-databases' > mysql-all-databases.sql
restic backup mysql-all-databases.sql --tag namespace:$NS --tag mysql-dump
rm -f mysql-all-databases.sql
```

Validate the label selector in your rendered manifests before relying on this command.

## 6. Retention policy

A typical small-production retention policy:

```bash
restic forget \
  --keep-hourly 24 \
  --keep-daily 14 \
  --keep-weekly 8 \
  --keep-monthly 12 \
  --prune
restic check --read-data-subset=1/20
```

Run `restic check` after repository maintenance and alert on failures.

## 7. Restore drill: same node

1. Stop the release.
2. Move the damaged PVC directory aside; do not delete it until the restore is verified.
3. Restore the correct snapshot to a temporary directory.
4. Copy restored data into the PVC path preserving ownership and permissions.
5. Start workloads and run smoke/application tests.

Example outline:

```bash
NS=ontoportal
RELEASE=ontoportal
PVC=${RELEASE}-shared-data
SNAPSHOT=latest
TARGET=/restore/${PVC}
REPLICAS_FILE=/tmp/${RELEASE}-restore-replicas.$(date +%s).txt

kubectl -n "$NS" get deploy -l app.kubernetes.io/instance="$RELEASE" \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.replicas}{"\n"}{end}' > "$REPLICAS_FILE"
kubectl -n "$NS" scale deploy -l app.kubernetes.io/instance="$RELEASE" --replicas=0

sudo mkdir -p "$TARGET"
sudo -E restic restore "$SNAPSHOT" --target "$TARGET"
# Confirm restored tree, then rsync into the confirmed local-path PVC directory.
# sudo rsync -aHAX --delete "$TARGET/<path-inside-snapshot>/" /var/lib/rancher/k3s/storage/<confirmed-pvc-path>/

while read -r name replicas; do
  kubectl -n "$NS" scale deploy "$name" --replicas="${replicas:-1}"
done < "$REPLICAS_FILE"
SMOKE_DEEP=true scripts/smoke.sh "$NS" "$RELEASE"
```

## 8. Restore drill: new namespace

A better restore test restores into a new namespace without overwriting the source deployment:

1. Create a new namespace such as `ontoportal-restore`.
2. Create restored PVCs or pre-populate PVC host paths from Restic.
3. Create a new Secret with restored or rotated credentials.
4. Install the chart with the same profile and a restore-specific site values file.
5. Run smoke tests and ontology/search/admin checks.
6. Document gaps and remove the restore namespace.

## 9. Backup schedule

For a small single-node server:

- nightly Restic backup of PVC paths after a maintenance-window quiesce;
- nightly MySQL/RDF/Solr application-native dumps when applicable;
- weekly `restic check --read-data-subset`;
- monthly full restore drill to a new namespace or standby server;
- offline copy or object-lock repository for ransomware protection.

For HA production:

- frequent database/search/RDF native backups;
- Kubernetes object backups with Velero or equivalent;
- PVC backups through VolSync/CSI snapshots/node-agent;
- etcd snapshots for k3s servers;
- alerts for every failed backup and stale latest snapshot.

## 10. What to record for every restore drill

```text
Date:
Cluster/node:
Repository snapshot ID:
Namespace/release:
PVCs restored:
Commands used:
Data loss window:
Smoke-test result:
Ontology import/search/admin result:
Issues found:
Fixes/docs updated:
Next scheduled drill:
```

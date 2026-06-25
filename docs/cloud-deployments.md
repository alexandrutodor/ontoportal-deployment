# Cloud provider deployment overlays

The Terraform module in this repository installs OntoPortal into an existing
Kubernetes cluster. It does not create EKS, AKS, GKE, VPCs, node pools, managed
identity, DNS, or cloud databases. Cloud-specific behavior is represented as
values overlays that can be combined with any distribution profile.

## AWS EKS

Use:

```bash
helm template agroportal chart/ontoportal \
  -f values/profiles/agroportal-clean.yaml \
  -f values/profiles/production-recommended.yaml \
  -f values/cloud/aws-eks.yaml
```

Or Terraform:

```bash
cd terraform
cp examples/aws-eks.tfvars.example aws-eks.auto.tfvars
terraform init
terraform plan
```

`values/cloud/aws-eks.yaml` assumes:

- a cluster already exists;
- the AWS Load Balancer Controller reconciles `alb` ingress resources;
- gp3/EBS storage is available for RWO volumes;
- EFS or another RWX storage class is added separately before API/UI horizontal
  scaling beyond one replica.

For API/UI horizontal scaling, add a site-specific EFS overlay or adapt
`values/cloud/aws-eks-rwx-efs.example.yaml` after proving the EFS CSI driver,
permissions, backup, throughput, and latency are acceptable.

## Azure AKS

Use:

```bash
helm template matportal chart/ontoportal \
  -f values/profiles/matportal.yaml \
  -f values/profiles/production-recommended.yaml \
  -f values/cloud/azure-aks.yaml
```

Or Terraform:

```bash
cd terraform
cp examples/azure-aks.tfvars.example azure-aks.auto.tfvars
terraform init
terraform plan
```

`values/cloud/azure-aks.yaml` assumes:

- a cluster already exists;
- AKS CSI storage classes such as `managed-csi` are available;
- Application Gateway Ingress Controller or an equivalent ingress controller is
  installed and selected by the overlay annotations;
- Azure Files or another RWX storage class is added separately before API/UI
  horizontal scaling beyond one replica.

For API/UI horizontal scaling, adapt
`values/cloud/azure-aks-rwx-files.example.yaml` only after testing file locking,
performance, backup, and pod identity/security requirements.

## Google Kubernetes Engine

Use:

```bash
helm template ontoportal chart/ontoportal \
  -f values/profiles/ontoportal-clean.yaml \
  -f values/profiles/production-recommended.yaml \
  -f values/cloud/gcp-gke.yaml
```

Or Terraform:

```bash
cd terraform
cp examples/gcp-gke.tfvars.example gcp-gke.auto.tfvars
terraform init
terraform plan
```

`values/cloud/gcp-gke.yaml` assumes:

- a GKE cluster already exists;
- the built-in GKE Ingress controller is selected with the
  `kubernetes.io/ingress.class` annotation, so `ingress.useClassNameField=false`;
- `standard-rwo` is acceptable for default RWO persistent volumes;
- Filestore or another RWX storage class is added separately before API/UI
  horizontal scaling beyond one replica.

For API/UI horizontal scaling, adapt
`values/cloud/gcp-gke-rwx-filestore.example.yaml` only after enabling/testing the
managed Filestore CSI driver and reviewing regional availability, quota, backup,
and throughput.

## Local cloud emulation feasibility

- **AWS:** MiniStack/LocalStack is useful for local AWS data-plane spikes (STS,
  Secrets Manager, S3, and similar services) and validates request/response
  behavior, but it is not EKS/IAM/Control Plane parity.
  Use real AWS for identity, managed nodes, networking, and add-on behavior.
- **Azure:** Topaz is useful for health and preview smoke (`/health`), but ARM-like
  probes are mostly `401`/`404` without auth. Validate full ARM and provider
  behavior with a real Azure tenant/session before production-path decisions.
- **GCP:** no mature local Vertex AI emulator is available; real account-backed
  Vertex smoke should be used for model-path verification.
  In this run, `aiplatform` and `secretmanager` were enabled, while `container`
  (GKE API) was blocked/disabled in-session, so full GKE cluster-level validation
  remains pending until enabled.
- Other useful local emulators for broader integration spikes:
  - Azurite (Blob/Queue/Table),
  - Azure Service Bus / Event Hubs / Cosmos emulator,
  - Lowkey Vault,
  - MinIO / Moto / DynamoDB Local,
  - official GCP service-specific emulators for supported APIs (for example
    Pub/Sub, Storage, Firestore, Datastore), but not Vertex AI or Secret
    Manager.

## Common cloud checklist

Before promoting any cloud overlay:

1. Replace generated/chart-managed secrets with External Secrets or existing
   Kubernetes Secrets.
2. Pin every application image to an immutable tag or digest.
3. Set real hosts and TLS certificate references in a private site overlay.
4. Verify ingress controller behavior with `helm template`, live install, and
   browser smoke tests.
5. Verify every StorageClass and access mode with a real PVC and restart/drain
   test.
6. Keep API/UI at one replica unless shared `/data` is RWX or mutable state has
   been externalized.
7. Run `scripts/smoke.sh`, Playwright UI tests, backup/restore drills, and
   autoscaling checks on the target cluster.
8. Record provider-specific acceptance evidence before production use.

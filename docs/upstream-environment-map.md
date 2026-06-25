# Upstream deployment environment map

This repository intentionally does not copy any single upstream deployment style
verbatim. It translates the published OntoPortal/BioPortal/AgroPortal deployment
patterns into reusable layers that can be recombined for local, source-build,
and cloud Kubernetes targets.

## Public patterns reviewed

| Upstream pattern | Useful deployment behavior | Repository implementation |
| --- | --- | --- |
| OntoPortal Docker/DIP | Compose-style local workflows can run only backing services, run API/cron from containers, or mount/build application source. Provisioning prepares the RDF store, admin account, and semantic-type data. | `values/profiles/docker-compose.yaml`, Compose rendering, source-build values, and environment recipes such as `bioportal-compose-source.yaml`. Runtime provisioning remains explicit rather than hidden in chart startup. |
| BioPortal virtual appliance | Full-stack appliance packages API, UI, cron, RDF store, Solr, MySQL, Redis, memcached, and OS/service bootstrap for VM/cloud-image users. | Kubernetes chart models the same core runtime components; cloud overlays and Terraform install into an existing EKS/AKS/GKE/k3s cluster instead of building cloud images. |
| AgroPortal Docker Swarm | Uses separate API/UI stack files, shared overlay networking, image overrides, environment files, and post-deploy admin/STY provisioning. | `agroportal-clean` profile, reusable add-ons, generated Compose output, and environment recipes keep API/UI/runtime choices separate. |
| OntoPortal UI development docs | UI development can target an existing appliance/API while the UI is built locally, including distribution-specific branches. | Source-build values allow a deployment to point UI/API/cron components at Git repositories and promote built images through generated `image-values.yaml`. |

## Translation rules

1. **Do not fork the chart for each distribution.** Differences belong in
   `values/profiles`, `values/cloud`, `values/addons`, `values/image-builds`, or
   private `values/sites` files.
2. **Do not hide provisioning inside a pod startup command.** Admin creation,
   semantic-type loading, ontology bootstrap, and one-time migrations should be
   explicit runbook/Job work with idempotency and recorded output.
3. **Use existing images by default.** Source builds are opt-in and produce an
   image promotion artifact rather than changing application code in place.
4. **Provider overlays describe cluster assumptions, not cloud infrastructure.**
   EKS/AKS/GKE clusters, identities, DNS, certificate issuers, databases, and
   backup stores are still provisioned by the platform team or a separate IaC
   layer.
5. **Keep horizontal scaling gated.** API/UI replicas greater than one require
   tested RWX storage or externalized mutable state. VPA starts in recommendation
   mode and KEDA/HPA need live metrics and load tests.

## Reusable layer matrix

| Concern | Layer | Examples |
| --- | --- | --- |
| Distribution identity and defaults | `values/profiles/*.yaml` | `ontoportal-clean`, `agroportal-clean`, `matportal` |
| Runtime/provider assumptions | `values/profiles/k3s-*.yaml`, `values/cloud/*.yaml` | k3s local/CI, AWS EKS, Azure AKS, GKE |
| Optional product/platform features | `values/addons/*.yaml` | Matomo, FAIRness, assistant, monitoring, HPA, KEDA, VPA, backup, policy |
| Image source and registry | `values/image-builds/*.yaml` | OntoPortal, BioPortal, AgroPortal source-build plans |
| Site/private deployment choices | `values/sites/*.yaml` | hosts, TLS, external secret names, immutable image pins, final sizing |
| Integrated target | `environments/*.yaml` | Compose existing images, source-built BioPortal-style Compose, AgroPortal on EKS, MatPortal on AKS, OntoPortal on GKE |

## Adding a new deployment

1. Pick the closest distribution profile.
2. Add one provider/runtime overlay, or create a small new overlay if the storage
   or ingress behavior is genuinely different.
3. Add only the required add-ons.
4. Choose `deploymentTarget.imageMode=existing` with pinned image values, or add
   an `imageBuilds` overlay and promote built images through `image-values.yaml`.
5. Create an `environments/<name>.yaml` recipe that lists the layers in order.
6. Run `make validate`, render the environment, then run Helm/Docker/Terraform
   checks in an environment with those tools installed.

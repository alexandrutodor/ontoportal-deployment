# Repository analysis summary

## Existing uploaded Kubernetes tree

The source tree contains a large amount of useful operational work, especially around k3s, monitoring, local development scripts, UI overrides, assistant experiments, and MatPortal-specific runbooks. The deployable chart, however, is now organized as a clean OntoPortal chart with optional overlays.

Main findings:

- `charts/matportal-ontoportal` is named and described as MatPortal.
- Resource names and service references are tied to MatPortal naming.
- API startup includes runtime patching and hotfix logic that should not be present in a clean OntoPortal profile.
- UI startup includes MatPortal overrides, Matomo hooks, assistant hooks, MOBI sync, OAuth/Keycloak assumptions, and MatPortal strings.
- Optional components exist but are not consistently isolated as add-ons.
- k3s-specific node/storage behavior is mixed with application behavior.
- Terraform is useful for the current infrastructure but is not a reusable chart deployment layer.

## Existing Docker repositories

The MatPortal Docker repository is a good reference for persistent single-host deployment. The upstream and AgroPortal Docker repositories are useful compatibility references. They should not be copied as the new source of truth; otherwise, Kubernetes and Compose will drift.

## Conversion performed in this repository

- Created a generic `ontoportal` Helm chart.
- Created separate clean, AgroPortal, MatPortal, k3s, and Compose values profiles.
- Moved MatPortal behavior into profile/add-on values and named patch gates.
- Added a Compose renderer that reads the same Helm values.
- Added Terraform that installs the Helm chart to an existing k3s cluster.
- Added optional platform add-ons for monitoring, Trivy, SonarQube, and Wazuh wrapper.
- Added docs and runbooks for deployment, maintenance, migration, and security add-ons.

## Items still requiring real-cluster validation

- Exact upstream image entrypoints and app directories for each selected OntoPortal/AgroPortal/MatPortal image tag.
- Solr configset initialization for strict upstream compatibility.
- Virtuoso container behavior and persistent data layout for the chosen image.
- UI database bootstrap/migration commands for the selected UI image.
- Runtime patch compatibility with current MatPortal application code.
- Ingress path rewriting rules for each production host.

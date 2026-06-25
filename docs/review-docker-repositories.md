# Review of Docker deployment repositories

## `matportal/ontoportal_docker`

The MatPortal Docker repository is useful as a reference for single-host persistence and operational scripting. The README describes a Compose-based appliance with bind-mounted writable paths, `.env`-driven admin bootstrap, and commands for starting API/UI or the whole stack.

For this repository, it should not become the primary source of truth because it would create a second deployment surface next to Kubernetes. Instead, this repository renders Compose from the same Helm values profiles.

## `ontoportal/ontoportal_docker`

Use upstream `ontoportal_docker` as the compatibility reference for service composition and provisioning. The clean profile stays compatible with upstream-style images and configuration without MatPortal runtime patches.

## `agroportal/ontoportal_docker`

The AgroPortal fork is a useful compatibility target because it tracks a community deployment variant. This repository includes `values/profiles/agroportal-clean.yaml` so differences can be modeled as values rather than template forks.

## Decision

Create a new Kubernetes-first deployment repository based on the current Kubernetes work, but cleanly split it into:

- generic chart templates;
- clean OntoPortal values;
- AgroPortal-compatible values;
- MatPortal values;
- optional add-ons;
- generated Compose.

This keeps future updates maintainable across Kubernetes, Terraform, and Compose.

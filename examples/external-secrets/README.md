# External Secrets example

This directory contains a complete k3s-friendly External Secrets Operator (ESO) example for the OntoPortal secret contract.

It uses ESO's Kubernetes provider so the example can be rehearsed on any k3s cluster without cloud credentials:

1. A source Secret lives in `ontoportal-secret-source`.
2. ESO is granted read-only access to that source Secret.
3. A `ClusterSecretStore` points ESO at the in-cluster Kubernetes API.
4. An `ExternalSecret` materializes `ontoportal-secrets` in the application namespace.
5. Helm installs OntoPortal with `secrets.create=false` and `secrets.existingSecret=ontoportal-secrets`.

For production, keep the `ExternalSecret` target key names but replace the Kubernetes provider with Vault, AWS Secrets Manager, GCP Secret Manager, Azure Key Vault, 1Password, SOPS, or another approved secret backend.

## Install ESO

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace external-secrets --create-namespace \
  -f values/addons/external-secrets.yaml
kubectl -n external-secrets rollout status deploy/external-secrets --timeout=5m
```

## Apply the example

Edit `kubernetes-provider-source.example.yaml` first and replace all `replace-with-*` values.

```bash
kubectl create namespace ontoportal || true
kubectl apply -f examples/external-secrets/kubernetes-provider-source.example.yaml
kubectl apply -f examples/external-secrets/ontoportal-externalsecret.yaml
kubectl -n ontoportal get externalsecret,secret ontoportal-secrets
```

Wait for `READY=True`:

```bash
kubectl -n ontoportal get externalsecret ontoportal-secrets
kubectl -n ontoportal describe externalsecret ontoportal-secrets
```

## Install OntoPortal with the synced Secret

```bash
helm upgrade --install ontoportal chart/ontoportal \
  --namespace ontoportal \
  -f values/profiles/ontoportal-clean.yaml \
  -f values/profiles/k3s-local.yaml \
  --set global.createNamespace=false \
  --set secrets.create=false \
  --set secrets.existingSecret=ontoportal-secrets
```

For MatPortal, change the namespace/release and use the MatPortal profile/add-ons, but keep the same target Secret key contract unless a site overlay intentionally changes it.

## Security notes

- Do not commit real secrets into the source Secret example.
- Keep ESO backend permissions read-only and scoped to the minimum secret paths.
- Use `deletionPolicy: Retain` for long-lived environments so uninstalling the `ExternalSecret` does not destroy live application credentials.
- Protect Helm/Terraform state and CI logs; `secrets.existingSecret` avoids putting secret values into Helm release history.

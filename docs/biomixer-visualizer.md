# BioMixer replacement visualizer

The [OntoPortal BioMixer Visualizer](https://github.com/ontoportal/biomixer-visualizer) is the maintained replacement for the legacy BioMixer embed. It is a static application packaged as the optional `ontopanel` deployment component.

## Enable it

Add the visualizer overlay to an OntoPortal install:

```bash
helm upgrade --install ontoportal chart/ontoportal \
  --namespace ontoportal \
  -f values/profiles/ontoportal-clean.yaml \
  -f values/profiles/k3s-local.yaml \
  -f values/addons/biomixer-visualizer.yaml
```

The overlay:

- deploys `ghcr.io/ontoportal/biomixer-visualizer` on port 8000;
- exposes it at `/visualizer` on the UI ingress host;
- sets `ONTOPANEL_VISUALIZER_URL=/visualizer/` in the Web UI container.

Before enabling the replacement, verify that the configured `images.ontopanel` image is pullable from the deployment nodes. For a registry that requires authentication, use the existing `global.imagePullSecrets`. Alternatively, run the source-build plan to an accessible registry and override `images.ontopanel` with the resulting image. Do not invent or repoint to an unverified public image. The current GHCR release is an external gate: an anonymous token request returns HTTP 401, and package visibility requires an OntoPortal organization/package administrator.

Enable the `biomixer_replacement` feature in OntoPortal Web UI after deployment. Until then, Web UI continues to use its existing BioMixer configuration.

For a different public location, override the URL:

```yaml
ui:
  ontopanelVisualizerUrl: https://visualizer.example.org/

ontopanel:
  enabled: false
```

This supports hosting the static application separately without deploying the chart component.

## Build from source

The public source-build plan includes the visualizer repository:

```bash
python3 scripts/image-build-matrix.py \
  -f values/image-builds/ontoportal-source.yaml
```

Use an immutable image tag or digest in production rather than the default `main` tag.

## Docker Compose

Enable `ontopanel` in a Compose values overlay. The generated visualizer service is published on `ONTOPANEL_PORT` (8000 by default), and Web UI receives its browser-accessible localhost URL. Set `ui.ontopanelVisualizerUrl` when users access Compose through a hostname other than localhost.

## Legacy compatibility

The new repository is a replacement, not a fork or redeployment of the legacy BioMixer source. Disabling the `biomixer_replacement` feature returns Web UI to its pre-replacement path and configuration.

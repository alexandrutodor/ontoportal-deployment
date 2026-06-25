# Generated Docker Compose files

Files in `compose/generated` are produced from Helm values by `scripts/render-compose.py`.

Generate all main profiles:

```bash
make compose-all
```

Generate a specific profile with add-ons:

```bash
python3 scripts/render-compose.py \
  -f values/profiles/matportal.yaml \
  -f values/profiles/docker-compose.yaml \
  -f values/addons/matomo.yaml \
  -f values/addons/fairness.yaml
```

Do not maintain generated Compose files by hand. Change `chart/ontoportal/values.yaml`, a profile, or an add-on overlay, then rerender.

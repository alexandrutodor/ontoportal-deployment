# Docker Compose deployment tutorial

Compose is included for development, demos, and small single-host deployments. Kubernetes remains the source of truth. Do not expose a Compose deployment with `change-me` credentials or without a TLS reverse proxy.

Prerequisites: Python 3 with PyYAML, Docker Compose v2, enough disk for `DATA_DIR`, and `curl` for smoke checks.

## 1. Render Compose

Clean OntoPortal:

```bash
python3 scripts/render-compose.py \
  -f values/profiles/ontoportal-clean.yaml \
  -f values/profiles/docker-compose.yaml
```

MatPortal:

```bash
python3 scripts/render-compose.py \
  -f values/profiles/matportal.yaml \
  -f values/profiles/docker-compose.yaml \
  -f values/addons/matomo.yaml \
  -f values/addons/fairness.yaml
```

## 2. Configure environment

```bash
cp compose/generated/.env.ontoportal-clean.sample .env
# edit DATA_DIR, ONTOPORTAL_API_KEY, and passwords
# set API_BIND=127.0.0.1 and UI_BIND=127.0.0.1 unless a trusted reverse proxy terminates TLS
```

## 3. Start

```bash
docker compose --env-file .env \
  -f compose/generated/docker-compose.ontoportal-clean.yml \
  config

docker compose --env-file .env \
  -f compose/generated/docker-compose.ontoportal-clean.yml \
  up -d
```

## 4. Inspect

```bash
docker compose --env-file .env -f compose/generated/docker-compose.ontoportal-clean.yml ps
docker compose --env-file .env -f compose/generated/docker-compose.ontoportal-clean.yml logs -f api
curl -fsS http://127.0.0.1:9393/
```

## 5. Stop without deleting data

```bash
docker compose --env-file .env -f compose/generated/docker-compose.ontoportal-clean.yml down
```

## 6. Delete data

```bash
docker compose --env-file .env -f compose/generated/docker-compose.ontoportal-clean.yml down
rm -rf ./data
```

If you changed `DATA_DIR`, delete that configured directory instead of `./data`.

## 7. Compose maintenance rule

Do not hand-edit files under `compose/generated`. Change Helm values and rerender Compose instead.

```bash
make compose-all
make validate
```

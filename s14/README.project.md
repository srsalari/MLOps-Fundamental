# churn-mlops

A small but complete, reproducible ML service on-prem: customer churn prediction, from versioned data to a monitored
API on Kubernetes. Built step by step in the course "MLOps Fundamentals On-Prem".

Copy this file to the root of your project as `README.md` and replace every placeholder (a "less than" sign, the capital word FILL, a colon and a hint).
`scripts/readiness_check.sh` (item X1) fails while a placeholder is left. Delete this paragraph when you are done.

**Author:** <FILL: your name> · **Status:** <FILL: for example "course capstone, v1.0.0, readiness score 9x/100">

## What it does

- Trains a churn classifier (scikit-learn) on a synthetic customer dataset, with a 3-stage DVC pipeline
  (preprocess, train, evaluate) that reproduces the same metrics from the same data and parameters.
- Tracks every run in MLflow, registers the model, and promotes it with a gate: `@challenger` becomes `@champion`
  only if metrics pass the thresholds in `params.yaml`.
- Serves the `@champion` model with FastAPI (`/predict`, `/ready`, `/health`, `/metrics`) in a non-root image scanned with Trivy.
- Runs on Kubernetes (kind) behind a Traefik Ingress, packaged as a Helm chart with dev and prod values, with rollback.
- CI on Gitea Actions (lint, test, build, scan, push; metrics-diff comment on pull requests; scheduled retrain),
  Prometheus + Grafana dashboard (rate, errors, duration), alert rule, and an Evidently data-drift report.

Key numbers (from my own run): <FILL: roc_auc, f1, p95 latency, image size, readiness score>

## Architecture

```text
data (DVC, S3)  ->  dvc repro  ->  MLflow runs  ->  Registry (@challenger -> @champion)
                                                          |
                    image (Docker, Trivy)  <--- API (FastAPI, loads @champion)
                           |
            registry :5001 -> kind + Helm (dev / prod) -> Traefik Ingress (churn.localhost)
                                                          |
                            Prometheus -> Grafana, alert rules, Evidently drift report
```

| Part | Tool |
|---|---|
| Git, CI | Gitea, Gitea Actions |
| Data and pipeline | DVC 3.67.1, SeaweedFS (S3 API) |
| Tracking and registry | MLflow 3.17.2 (SQLite backend, artifacts on S3) |
| Serving | FastAPI, uvicorn, Docker, Trivy |
| Platform | kind, Helm, Traefik, Ansible (VM path) |
| Monitoring | Prometheus, Grafana, Evidently |

## Quick start

Needs Docker, `uv`, `git`, `make`, `kubectl`, `helm`, `kind`. On Windows use WSL Ubuntu.

```bash
git clone <FILL: your repository URL> churn-mlops && cd churn-mlops
```

```bash
cp .env.example .env     # then put your lab S3 keys and the MLflow lines in .env (see RUNBOOK.md)
```

```bash
set -a; source .env; set +a
```

```bash
uv sync
```

```bash
uv run dvc pull
```

```bash
uv run dvc repro --force && make runs
```

Then register and promote (`make register RUN=<id>`, `make promote`), build (`make image TAG=1.0.0`), scan (`make scan TAG=1.0.0`),
and deploy (`make helm-deploy STAGE=dev HELM_ARGS="--set image.tag=1.0.0"`).

## Operations

Start, stop, restart, logs, rollback and known incidents are in [RUNBOOK.md](RUNBOOK.md).
The 5-minute demo script is in [DEMO.md](DEMO.md).

## Production readiness

`scripts/readiness_check.sh` scores the project out of 100 (reproducibility, model lifecycle, serving, deployment,
automation, documentation). My score: <FILL: score>. What I would do next: <FILL: two or three honest items>

## Limits (honest)

- Lab credentials and a single laptop: this is a mini production, not a production cluster.
- No Alertmanager, no autoscaling, no canary: those are the next course.

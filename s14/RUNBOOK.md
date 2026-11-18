# Runbook: churn-api

Template pre-filled for the churn service of the course. Copy it to the root of your project as `RUNBOOK.md`,
then replace every placeholder (each one is a "less than" sign, the capital word FILL, a colon and a hint) with your own owner, links and numbers.
`scripts/readiness_check.sh` (item X2) fails while a placeholder is left in this file. Delete this paragraph when you are done.

This file REPLACES the 6-line `RUNBOOK.md` of session 10. Its three commands (restart, logs, rollback on the VM)
live on in the section "Legacy: the VM with systemd" at the end.

## Service card

| Item | Value |
|---|---|
| What it does | Predicts customer churn: `POST /predict` returns `churn_probability`, `churn`, `threshold`, `model_version` |
| Owner / on-call | <FILL: your name and how to reach you> |
| Where it runs | kind cluster `mlops` (context `kind-mlops`), namespace `churn`, Helm release `churn-api`; image `localhost:5001/churn-api:<tag>` |
| Entry point | Traefik Ingress: `http://churn.localhost:8080` (dev). Prod release: namespace `churn-prod`, `http://prod.churn.localhost:8080` |
| Model | MLflow registry `churn`; dev serves `models:/churn@champion`, prod is pinned to one version (`models:/churn/N`) |
| Depends on | MLflow (`mlflow:5000`), SeaweedFS S3 (`seaweedfs:8333`), local registry (`localhost:5001`) |
| Dashboards | Grafana `http://localhost:3001` (admin, password `mlops-lab`, lab only), dashboard "Churn API: RED metrics"; Prometheus `http://localhost:9090` |
| Repository | <FILL: Gitea URL of the repo> (tags `vX.Y.Z`; this runbook is for `v1.0.0`) |
| SLO used in the demo | <FILL: for example "99 % of /predict answers under 200 ms, 5xx under 1 %">, measured on the Grafana dashboard |

## Start

Lab services first (SeaweedFS, MLflow, Gitea), then the cluster, then the service.

```bash
cd ~/mlops-lab/compose && docker compose up -d seaweedfs mlflow gitea
```

```bash
docker start kind-registry mlops-control-plane
```

```bash
cd ~/work/churn-mlops && make helm-deploy STAGE=dev
```

Monitoring (optional, needed for the dashboard):

```bash
cd ~/work/churn-mlops && make mon-up
```

## Health check

Run these three; all must answer.

```bash
curl -fsS http://churn.localhost:8080/health
```

```bash
curl -fsS http://churn.localhost:8080/ready
```

Expected: `{"status":"ready","model_version":"<N>"}` where N is the version that has the alias `@champion` (`make models`).
`/ready` answers `503 {"detail":"model not loaded"}` when the model could not be loaded: this is the signal that MLflow or the model URI is wrong.

```bash
cd ~/work/churn-mlops && scripts/readiness_check.sh
```

The score must stay at or above the value you wrote in your DEMO (80 or more).

## Stop

Stop the service but keep the cluster and the data:

```bash
helm --kube-context kind-mlops uninstall churn-api -n churn
```

Stop everything on the laptop (data is kept: never add `-v`):

```bash
cd ~/work/churn-mlops && make mon-down
```

```bash
docker stop mlops-control-plane kind-registry
```

```bash
cd ~/mlops-lab/compose && docker compose down
```

## Restart

Restart one pod (the ReplicaSet creates a new one in about 6 seconds; users keep being served by the other pods when replicas > 1):

```bash
kubectl --context kind-mlops -n churn delete pod -l app.kubernetes.io/name=churn-api
```

```bash
kubectl --context kind-mlops -n churn rollout status deployment/churn-api --timeout=120s
```

Do not use `kubectl rollout undo`, `set image` or `edit` on this Deployment: Helm owns it. Change things with `helm upgrade` or `make helm-deploy`.

## Logs

The API writes one JSON line per request (fields `ts`, `level`, `event`, `method`, `path`, `status`, `ms`).

```bash
kubectl --context kind-mlops -n churn logs deploy/churn-api --tail=50
```

Only the errors, from all pods:

```bash
kubectl --context kind-mlops -n churn logs -l app.kubernetes.io/name=churn-api --tail=200 | grep '"level": "ERROR"'
```

The model load error (`model_load_failed ...`) appears at pod start, so use `--tail` large enough or `--since=10m`.
Metrics instead of logs: `http://localhost:9090/graph`, query `sum(rate(http_requests_total{job="churn-api",status="5xx"}[1m]))`.

## Rollback

Which revisions exist, and which one was good:

```bash
cd ~/work/churn-mlops && make helm-status
```

Go back to a good revision (this creates a NEW revision "Rollback to N"; the ConfigMap with the model URI is rolled back too):

```bash
cd ~/work/churn-mlops && make helm-rollback REV=<N>
```

Serve an older model without a new image (dev release, keep the other values):

```bash
cd ~/work/churn-mlops && make helm-deploy STAGE=dev HELM_ARGS="--set config.modelUri=models:/churn/1"
```

Move the champion alias back in the registry (the dev release picks it up after a pod restart, see "Restart"):

```bash
cd ~/work/churn-mlops && MLFLOW_DISABLE_AGENT_HINT=1 MLFLOW_TRACKING_URI=http://localhost:5050 uv run python -c "from mlflow import MlflowClient; MlflowClient().set_registered_model_alias('churn', 'champion', 1)"
```

Replace `1` by the version you want. Check with `make models`.

## Known incidents

| Symptom | Likely cause | First action |
|---|---|---|
| `/ready` is `503`, pods `0/1 Running` | model URI wrong (e.g. `models:/churn/99`) or MLflow down | `kubectl --context kind-mlops -n churn logs deploy/churn-api --tail=100`, then `make helm-rollback REV=<N>`; MLflow: `curl http://localhost:5050/health` |
| Pods `ImagePullBackOff` | image tag is not in the registry | `curl http://localhost:5001/v2/churn-api/tags/list`; `make push TAG=<tag>` |
| Ingress answers `404 page not found` | wrong Host header or the Ingress is missing | `kubectl --context kind-mlops -n churn get ingress`; use `churn.localhost` |
| `helm upgrade` says `UPGRADE FAILED ... context deadline exceeded` | new pods never became ready; old pods still serve | `make helm-status`, read the pod events, `make helm-rollback REV=<N>` |
| Dashboard shows `No data` | no traffic, or Prometheus target down | `make load DURATION=60`, `make mon-status` |
| Alert `ChurnApiDown` is firing | the monitored API container stopped | `docker ps -a --filter name=churn-api-mon`, `make api-fix` |
| Drift report says "3 of 7 columns drifted" | data of the new period differs from training data | read `reports/drift-v1-v2.html`; decide to retrain: `uv run dvc repro`, `make register RUN=<id>`, `make promote` |
| <FILL: one incident you met yourself> | <FILL: cause> | <FILL: what you did> |

## Change log

| Version | What changed | How to go back |
|---|---|---|
| v1.0.0 | Capstone release: clean-clone verified, readiness score <FILL: your score>/100 | `make helm-rollback REV=<N>` |

## Legacy: the VM with systemd (session 10)

Still valid for the practice VM (`make vm-up`, `make deploy`).

```bash
sudo systemctl restart churn-api
```

Logs of the VM service: `/var/log/churn-api/api.log`.

```bash
make rollback VERSION=1
```

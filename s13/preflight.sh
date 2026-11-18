#!/usr/bin/env bash
# =============================================================================
# s13/preflight.sh — ready for session 13? Run it BEFORE class:
#     ~/mlops-lab/s13/preflight.sh                 (PROJECT=/path to check another folder)
# Checks the laptop (Docker memory, images, ports 9090/3001/8003) and that
# ~/work/churn-mlops is at the end state of session 12, plus what the lab needs:
# Gitea and the runner image, the local registry, MLflow with @champion, the API image.
# Exit code: 0 = ready, 1 = something to fix. Read-only.
# =============================================================================
SESSION=13
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../scripts/preflight-lib.sh"
preflight_begin

s12_code()     { tracked chart/churn-api/Chart.yaml chart/churn-api/values.yaml k8s/ingress.yaml && grep -q '^helm-deploy:' Makefile; }
s09_champion() { CHAMP=$(mlf_get "api/2.0/mlflow/registered-models/alias?name=churn&alias=champion" \
                   | jq_py "print(d['model_version']['version'])") && [ -n "$CHAMP" ]; }
lab_network()  { docker network inspect mlops-lab >/dev/null 2>&1; }
ci_image()     { docker image inspect mlops/ci-job:1.0 >/dev/null 2>&1; }
api_image()    { docker image inspect churn-api:0.7.0 >/dev/null 2>&1; }
image_in_reg() { curl -fsS --max-time 5 http://localhost:5001/v2/churn-api/tags/list 2>/dev/null | grep -q '"0.7.0"'; }
runner_up()    { docker ps --format '{{.Names}}' 2>/dev/null | grep -q 'gitea-runner'; }
runner_token() { [ -n "$(sed -n 's/^RUNNER_TOKEN=//p' "$LAB/compose/.env" 2>/dev/null | tail -1 | tr -d '\r')" ]; }
docker_mem()   { M=$(docker info --format '{{.MemTotal}}' 2>/dev/null); [ -n "$M" ] && [ "$M" -ge 6000000000 ]; }
dvc_remote()   { [ -f .dvc/config ] && grep -q 's3://dvc' .dvc/config && git rev-parse -q --verify refs/tags/data-v1 >/dev/null && git rev-parse -q --verify refs/tags/data-v2 >/dev/null; }
pyproj_ok()    { grep -q 'prometheus-fastapi-instrumentator' pyproject.toml; }

if project_begin "end of session 12"; then
  soft  on_main  "on branch main"                                   "git switch main && git pull"
  check s12_code "chart/churn-api, k8s/ingress.yaml and the helm targets are committed" "s12/README.md, steps 2 and 3"
  check dvc_remote "DVC remote s3://dvc/... is configured and the tags data-v1 and data-v2 exist (the drift report needs both)" "s04/README.md, steps 3 and 5"
  check pyproj_ok "the API exposes /metrics (prometheus-fastapi-instrumentator is a dependency)" "s08/README.md"
  check_tag v0.10.0 "session 12" s12
fi
echo "[Lab services]"
svc_s3
svc_mlflow
svc_gitea
check s09_champion "registered model 'churn' has the alias @champion (the monitoring API loads it)" "make promote   (s07/README.md, step 3)"
[ -n "${CHAMP:-}" ] && info "@champion = version $CHAMP"
check lab_network "Docker network mlops-lab exists" "cd ~/mlops-lab/compose && docker compose up -d seaweedfs mlflow"
echo "[CI and monitoring needs]"
check ci_image    "the CI job image mlops/ci-job:1.0 is loaded (the runner starts every job in it)" "install-from-bundle.sh loads it; ask the trainer (it cannot be pulled from the internet)"
check api_image   "the image churn-api:0.7.0 exists locally (the monitoring API uses it)" "make image   (in the project, session 9)"
check image_in_reg "churn-api:0.7.0 is in the local registry localhost:5001 (CI pushes its image there)" "docker start kind-registry   or   make k8s-up   (session 11)"
soft  runner_token "RUNNER_TOKEN is set in ~/mlops-lab/compose/.env" "step 1 of the lab creates it (Gitea > Site Administration > Actions > Runners)"
soft  runner_up   "the Gitea runner container is running" "step 1: make runner-up"
soft  docker_mem  "Docker has at least 6 GB of memory (Prometheus + Grafana + CI jobs)" "Docker Desktop > Settings > Resources > Memory"
preflight_end

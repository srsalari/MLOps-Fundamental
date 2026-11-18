#!/usr/bin/env bash
# =============================================================================
# s14/preflight.sh — ready for session 14? Run it BEFORE class:
#     ~/mlops-lab/s14/preflight.sh                 (PROJECT=/path to check another folder)
# Checks the laptop (Docker memory, images, ports) and that ~/work/churn-mlops is at the end
# state of session 13, and that everything the end-to-end run needs is running: lab services,
# registry, the kind cluster with Traefik and the Helm release, Prometheus and Grafana.
# Exit code: 0 = ready, 1 = something to fix. Read-only.
# =============================================================================
SESSION=14
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../scripts/preflight-lib.sh"
preflight_begin

KCTX="${KCTX:-kind-mlops}"
s13_code()     { tracked .gitea/workflows/ci.yaml .gitea/workflows/ml-ci.yaml .gitea/workflows/retrain.yaml monitoring/docker-compose.yml scripts/drift_report.py && grep -q '^mon-up:' Makefile; }
dvc_remote()   { [ -f .dvc/config ] && grep -q 's3://dvc' .dvc/config && has_tag data-v1 && has_tag data-v2; }
champion()     { CHAMP=$(mlf_get "api/2.0/mlflow/registered-models/alias?name=churn&alias=champion" | jq_py "print(d['model_version']['version'])") && [ -n "$CHAMP" ]; }
docker_mem()   { M=$(docker info --format '{{.MemTotal}}' 2>/dev/null); [ -n "$M" ] && [ "$M" -ge 6000000000 ]; }
cluster_up()   { kubectl --context "$KCTX" get nodes 2>/dev/null | grep -q ' Ready '; }
release_up()   { helm --kube-context "$KCTX" status churn-api -n churn -o json 2>/dev/null | grep -q '"status": *"deployed"'; }
ingress_ok()   { [ "$(http_code http://churn.localhost:8080/ready)" = 200 ]; }
registry_ok()  { curl -fsS --max-time 5 http://localhost:5001/v2/churn-api/tags/list 2>/dev/null | grep -q '"tags"'; }
prom_up()      { [ "$(http_code "${PROM_URL:-http://localhost:9090}/-/ready")" = 200 ]; }
grafana_up()   { [ "$(http_code "${GRAFANA_URL:-http://localhost:3001}/api/health")" = 200 ]; }
no_clean_dir() { [ ! -e "$HOME/work/churn-clean" ]; }
trivy_db()     { [ -d "${TRIVY_CACHE_DIR:-$HOME/.cache/trivy}/db" ]; }
pypi_ok()      { [ "$(http_code https://pypi.org/simple/)" = 200 ] || [ -n "${UV_DEFAULT_INDEX:-}" ]; }

if project_begin "end of session 13"; then
  soft  on_main  "on branch main"                                   "git switch main && git pull"
  check s13_code "CI workflows, monitoring/ and the drift script are committed" "s13/README.md, steps 1 to 4"
  check dvc_remote "DVC remote s3://dvc/... and the tags data-v1 and data-v2 exist" "s04/README.md, steps 3 and 5"
  check_tag v0.11.0 "session 13" s13
fi
echo "[Lab services]"
svc_s3
svc_mlflow
svc_gitea
check champion "registered model 'churn' has the alias @champion (the service loads it)" "make promote   (s07/README.md, step 3)"
[ -n "${CHAMP:-}" ] && info "@champion = version $CHAMP"
echo "[Kubernetes, registry and monitoring (the run needs all of them)]"
check registry_ok "the local registry answers on localhost:5001 and has churn-api" "docker start kind-registry   or   make k8s-up   (session 11)"
check cluster_up  "the kind cluster answers on context $KCTX (node Ready)"         "docker start mlops-control-plane   or   make k8s-up"
check release_up  "Helm release churn-api is deployed in namespace churn"          "make helm-deploy STAGE=dev   (session 12)"
check ingress_ok  "http://churn.localhost:8080/ready answers 200 through Traefik"  "make ingress-up   (session 12); port 8080 busy? see s12/README.md"
soft  prom_up     "Prometheus answers on 9090"                                      "make mon-up   (session 13)"
soft  grafana_up  "Grafana answers on 3001"                                         "make mon-up   (session 13)"
echo "[Needs of the clean-clone run]"
soft  docker_mem  "Docker has at least 6 GB of memory (kind + MLflow + monitoring + a build)" "Docker Desktop > Settings > Resources > Memory"
soft  trivy_db    "the Trivy database is in ${TRIVY_CACHE_DIR:-$HOME/.cache/trivy}"  "install-from-bundle.sh copies it there (make scan works offline only with it)"
soft  pypi_ok     "PyPI is reachable (uv sync in a clean clone downloads packages)"  "internet, or ask the trainer for the mirror (UV_DEFAULT_INDEX)"
soft  no_clean_dir "~/work/churn-clean does not exist yet (step 1 creates it)"       "mv ~/work/churn-clean ~/work/churn-clean.old   (or delete it if it is only a previous try)"
preflight_end

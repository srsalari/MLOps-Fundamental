#!/usr/bin/env bash
# =============================================================================
# s11/preflight.sh — ready for session 11? Run it BEFORE class:
#     ~/mlops-lab/s11/preflight.sh                 (PROJECT=/path to check another folder)
# Checks the laptop (kind, kubectl, node image, ports 8080/8443) and that
# ~/work/churn-mlops is at the end state of session 10, plus what the cluster
# needs: the S9 image in the local registry and MLflow with @champion.
# Exit code: 0 = ready, 1 = something to fix. Read-only.
# =============================================================================
SESSION=11
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../scripts/preflight-lib.sh"
preflight_begin

s10_code()     { tracked deploy/deploy.yml RUNBOOK.md && grep -q '^deploy:' Makefile; }
s09_image()    { docker image inspect churn-api:0.7.0 >/dev/null 2>&1; }
s09_registry() { curl -fsS --max-time 5 http://localhost:5001/v2/churn-api/tags/list 2>/dev/null | grep -q '"0.7.0"'; }
s09_champion() { CHAMP=$(mlf_get "api/2.0/mlflow/registered-models/alias?name=churn&alias=champion" \
                   | jq_py "print(d['model_version']['version'])") && [ -n "$CHAMP" ]; }
lab_network()  { docker network inspect mlops-lab >/dev/null 2>&1; }
no_cluster()   { ! kind get clusters 2>/dev/null | grep -qx mlops; }
docker_mem()   { M=$(( $(docker info -f '{{.MemTotal}}' 2>/dev/null || echo 0) / 1073741824 )); [ "$M" -ge 7 ]; }

if project_begin "end of session 10"; then
  soft  on_main  "on branch main"                                   "git switch main && git pull"
  check s10_code "deploy/ playbook, RUNBOOK.md and the deploy target are committed" "s10/README.md, steps 2-5"
  check_tag v0.8.0 "session 10" s10
fi
echo "[Lab services]"
svc_s3
svc_mlflow
check s09_champion "registered model 'churn' has the alias @champion" "make promote   (s07/README.md, step 3)"
[ -n "${CHAMP:-}" ] && info "@champion = version $CHAMP"
check lab_network "Docker network mlops-lab exists (the kind node joins it)" "cd ~/mlops-lab/compose && docker compose up -d seaweedfs mlflow"
echo "[Image for the cluster]"
check s09_image    "image churn-api:0.7.0 exists on the laptop"  "make image   (session 9)"
soft  s09_registry "churn-api:0.7.0 is in the local registry localhost:5001" "start the registry (s09/README.md, step 5) and make push — or make k8s-up first, then make push"
echo "[Cluster]"
check docker_mem "Docker has at least 8GB memory (the cluster needs about 1GB more)" "Docker Desktop: Settings > Resources; Colima: colima start --memory 8"
soft  no_cluster "no old kind cluster named mlops (make k8s-up creates it)" "an old one exists: fine if it is yours from a rehearsal; otherwise kind delete cluster --name mlops"
info "kind switches kubectl to context kind-mlops; current context now: $(kubectl config current-context 2>/dev/null || echo none)"
preflight_end

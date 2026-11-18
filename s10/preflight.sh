#!/usr/bin/env bash
# =============================================================================
# s10/preflight.sh — ready for session 10? Run it BEFORE class:
#     ~/mlops-lab/s10/preflight.sh                 (PROJECT=/path to check another folder)
# Checks the laptop (practice VM image, ports 2223/8090) and that ~/work/churn-mlops
# is at the end state of session 9: the container image work, tag v0.7.0, MLflow
# up with @champion (the service on the VM loads it at startup).
# Exit code: 0 = ready, 1 = something to fix. Read-only.
# =============================================================================
SESSION=10
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../scripts/preflight-lib.sh"
preflight_begin

s09_code()     { tracked Dockerfile .dockerignore && grep -q '^image:' Makefile; }
s09_champion() { CHAMP=$(mlf_get "api/2.0/mlflow/registered-models/alias?name=churn&alias=champion" \
                   | jq_py "print(d['model_version']['version'])") && [ -n "$CHAMP" ]; }
two_versions() { N=$(curl -fsS --max-time 10 -G "$MLFLOW_URI/api/2.0/mlflow/model-versions/search" --data-urlencode "filter=name='churn'" 2>/dev/null \
                   | jq_py "print(len(d.get('model_versions', [])))") && [ "${N:-0}" -ge 2 ]; }
ssh_client()   { command -v ssh >/dev/null && command -v ssh-keygen >/dev/null; }
old_vm()       { [ -z "$(docker ps -aq --filter name='^mlops-vm$' 2>/dev/null)" ]; }

if project_begin "end of session 9"; then
  soft  on_main  "on branch main"                                     "git switch main && git pull"
  check s09_code "Dockerfile, .dockerignore and the image target are committed" "s09/README.md, steps 2 and 5"
  check_tag v0.7.0 "session 9" s09
fi
echo "[Lab services]"
svc_s3
svc_mlflow
check s09_champion "registered model 'churn' has the alias @champion" "make promote   (s07/README.md, step 3)"
[ -n "${CHAMP:-}" ] && info "@champion = version $CHAMP"
soft two_versions "model 'churn' has at least 2 versions (needed for the rollback drill)" "register a second run: s07/README.md, step 2"
echo "[Practice VM]"
check ssh_client "ssh and ssh-keygen are installed" "Linux/WSL: sudo apt install openssh-client"
soft  old_vm     "no old container named mlops-vm (make vm-up creates it)" "an old one exists: docker rm -f mlops-vm   (only if you do not need it any more)"
preflight_end

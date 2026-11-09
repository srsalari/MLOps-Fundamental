#!/usr/bin/env bash
# =============================================================================
# s08/preflight.sh — ready for session 8? Run it BEFORE class:
#     ~/mlops-lab/s08/preflight.sh                 (PROJECT=/path to check another folder)
# Checks the laptop (port 8000 for the API) and that ~/work/churn-mlops is at the
# end state of session 7: registry code, tag v0.5.0, model 'churn' with @champion.
# Exit code: 0 = ready, 1 = something to fix. Read-only.
# =============================================================================
SESSION=08
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../scripts/preflight-lib.sh"
preflight_begin

s07_code()     { tracked src/churn/registry.py scripts/predict_champion.py params.yaml && grep -q '^gate:' params.yaml; }
s07_env()      { grep -q '^MLFLOW_ENABLE_PROXY_MULTIPART_DOWNLOAD=false' .env 2>/dev/null; }
s07_champion() { CHAMP=$(mlf_get "api/2.0/mlflow/registered-models/alias?name=churn&alias=champion" \
                   | jq_py "print(d['model_version']['version'])") && [ -n "$CHAMP" ]; }

if project_begin "end of session 7"; then
  soft  on_main  "on branch main"                                        "git switch main && git pull"
  check s07_code "registry.py, predict_champion.py and the gate: section in params.yaml are committed" "s07/README.md, step 2, then commit"
  check s07_env  ".env has MLFLOW_ENABLE_PROXY_MULTIPART_DOWNLOAD=false" "echo MLFLOW_ENABLE_PROXY_MULTIPART_DOWNLOAD=false >> .env"
  check_tag v0.5.0 "session 7" s07
fi
echo "[Lab services]"
svc_s3
svc_mlflow
check s07_champion "registered model 'churn' has the alias @champion" "make promote   (s07/README.md, step 3); did you run docker compose down -v?"
[ -n "${CHAMP:-}" ] && info "@champion = version $CHAMP"
svc_gitea
preflight_end

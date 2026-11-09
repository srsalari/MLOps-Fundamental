#!/usr/bin/env bash
# =============================================================================
# s09/preflight.sh — ready for session 9? Run it BEFORE class:
#     ~/mlops-lab/s09/preflight.sh                 (PROJECT=/path to check another folder)
# Checks the laptop (buildx, trivy, registry image, port 5001) and that
# ~/work/churn-mlops is at the end state of session 8: the FastAPI service,
# tag v0.6.0, MLflow up with @champion (the container loads it at startup).
# Exit code: 0 = ready, 1 = something to fix. Read-only.
# =============================================================================
SESSION=09
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../scripts/preflight-lib.sh"
preflight_begin

s08_code()     { tracked src/churn/api.py tests/test_api.py examples/customer.json && pinned fastapi uvicorn && grep -q '^serve:' Makefile; }
s08_champion() { CHAMP=$(mlf_get "api/2.0/mlflow/registered-models/alias?name=churn&alias=champion" \
                   | jq_py "print(d['model_version']['version'])") && [ -n "$CHAMP" ]; }
# Trivy must scan offline in class: its vulnerability database has to be on disk already.
trivy_db()     { for d in "${TRIVY_CACHE_DIR:-}" "$HOME/.cache/trivy" "$HOME/Library/Caches/trivy"; do
                   [ -n "$d" ] && [ -f "$d/db/trivy.db" ] && { TRIVY_DB=$d/db/trivy.db; return 0; }; done; return 1; }

if project_begin "end of session 8"; then
  soft  on_main  "on branch main"                                        "git switch main && git pull"
  check s08_code "api.py, test_api.py, examples, serve target committed; fastapi + uvicorn pinned" "s08/README.md, steps 1-2, then commit"
  check_tag v0.6.0 "session 8" s08
fi
echo "[Lab services]"
svc_s3
svc_mlflow
check s08_champion "registered model 'churn' has the alias @champion" "make promote   (s07/README.md, step 3)"
[ -n "${CHAMP:-}" ] && info "@champion = version $CHAMP"
echo "[Image scanning]"
soft trivy_db "Trivy vulnerability database is on disk (offline scan)" \
  "load it from the course pack (scripts/install-from-bundle.sh) or, with internet: trivy image --download-db-only"
[ -n "${TRIVY_DB:-}" ] && info "Trivy DB: $TRIVY_DB"
preflight_end

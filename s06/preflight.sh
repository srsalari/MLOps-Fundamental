#!/usr/bin/env bash
# =============================================================================
# s06/preflight.sh — ready for session 6? Run it BEFORE class:
#     ~/mlops-lab/s06/preflight.sh                 (PROJECT=/path to check another folder)
# Checks the laptop (MLflow server image, port 5050) and that ~/work/churn-mlops
# is at the end state of session 5: 3-stage DVC pipeline, tag v0.3.0.
# Exit code: 0 = ready, 1 = something to fix. Read-only (runs "dvc status").
# =============================================================================
SESSION=06
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../scripts/preflight-lib.sh"
preflight_begin

s05_stages()  { for s in preprocess train evaluate; do grep -qE "^  $s:" dvc.yaml 2>/dev/null || return 1; done; }
s05_tracked() { tracked dvc.yaml dvc.lock params.yaml src/churn/preprocess.py src/churn/evaluate.py; }
s05_status()  { uv run dvc status 2>&1 | grep -q "Data and pipelines are up to date"; }

if project_begin "end of session 5"; then
  soft  on_main     "on branch main"                                     "git switch main && git pull"
  check s05_stages  "dvc.yaml has the stages preprocess, train, evaluate" "s05/README.md, step 2"
  check s05_tracked "dvc.yaml, dvc.lock, params.yaml and the stage code are committed" "git add dvc.yaml dvc.lock params.yaml src && git commit"
  check_tag v0.3.0 "session 5" s05
fi
echo "[Lab services]"
svc_s3
[ "$IN_PROJECT" = yes ] && check s05_status "dvc status: Data and pipelines are up to date" "uv run dvc repro   then commit dvc.lock"
svc_gitea
preflight_end

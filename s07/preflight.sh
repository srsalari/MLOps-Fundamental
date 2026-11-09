#!/usr/bin/env bash
# =============================================================================
# s07/preflight.sh — ready for session 7? Run it BEFORE class:
#     ~/mlops-lab/s07/preflight.sh                 (PROJECT=/path to check another folder)
# Checks the laptop and that ~/work/churn-mlops is at the end state of session 6:
# MLflow tracking in evaluate.py, tag v0.4.0, MLflow server up with the 'churn' runs.
# Exit code: 0 = ready, 1 = something to fix. Read-only.
# =============================================================================
SESSION=07
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../scripts/preflight-lib.sh"
preflight_begin

s06_code() { pinned mlflow && grep -q mlflow src/churn/evaluate.py 2>/dev/null && tracked src/churn/evaluate.py uv.lock; }
s06_env()  { [ -n "$(envval MLFLOW_TRACKING_URI)" ]; }
s06_runs() { EXP_ID=$(mlf_get "api/2.0/mlflow/experiments/get-by-name?experiment_name=churn" | jq_py "print(d['experiment']['experiment_id'])") \
               && [ -n "$EXP_ID" ] \
               && N_RUNS=$(curl -fsS --max-time 10 -H 'Content-Type: application/json' \
                    -d "{\"experiment_ids\":[\"$EXP_ID\"],\"filter\":\"attributes.status = 'FINISHED'\",\"max_results\":100}" \
                    "$MLFLOW_URI/api/2.0/mlflow/runs/search" 2>/dev/null | jq_py "print(len(d.get('runs', [])))") \
               && [ "${N_RUNS:-0}" -ge 3 ]; }

if project_begin "end of session 6"; then
  soft  on_main  "on branch main"                                       "git switch main && git pull"
  check s06_code "mlflow pinned; evaluate.py logs to MLflow and is committed" "s06/README.md, steps 2-3, then commit"
  soft  s06_env  ".env has MLFLOW_TRACKING_URI"                          "echo MLFLOW_TRACKING_URI=http://localhost:5050 >> .env"
  check_tag v0.4.0 "session 6" s06
fi
echo "[Lab services]"
svc_s3
svc_mlflow
check s06_runs "experiment 'churn' has at least 3 finished runs (session 6 had 4)" \
  "did you run docker compose down -v? then redo s06/README.md step 4 (uv run dvc exp run ...)"
[ -n "${N_RUNS:-}" ] && info "finished runs in 'churn': $N_RUNS"
svc_gitea
preflight_end

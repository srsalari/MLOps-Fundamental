#!/usr/bin/env bash
# =============================================================================
# s02/preflight.sh — ready for session 2? Run it BEFORE class:
#     ~/mlops-lab/s02/preflight.sh                 (PROJECT=/path to check another folder)
# Checks the laptop (Docker, Gitea image, ports 3000/2222) and that the project
# ~/work/churn-mlops is at the end state of session 1.
# Exit code: 0 = ready, 1 = something to fix. Read-only.
# =============================================================================
SESSION=02
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../scripts/preflight-lib.sh"
preflight_begin

s01_files()   { for f in src/churn/train.py scripts/make_dataset.py configs/params.yaml Makefile uv.lock; do [ -f "$f" ] || return 1; done; }
s01_commit()  { git rev-parse --verify -q HEAD >/dev/null; }
s01_ignored() { [ -z "$(git ls-files data models metrics.json .env .venv 2>/dev/null)" ]; }
s01_outputs() { [ -f data/raw/churn.csv ] && [ -f models/model.joblib ]; }
compose_env() { [ -f "$LAB/compose/.env" ] || [ -f "$LAB/compose/.env.example" ]; }

if project_begin "end of session 1"; then
  check s01_files   "skeleton: src/churn/train.py, scripts/make_dataset.py, configs/params.yaml, Makefile, uv.lock" "copy the starter files again: s01/README.md, step 3"
  check s01_commit  "at least one commit exists"                    "git add . && git commit -m \"feat: project skeleton + baseline training\""
  check s01_ignored "data, models, metrics.json are NOT tracked by Git" "check .gitignore, then: git rm -r --cached data models metrics.json"
  soft  s01_outputs "data/raw/churn.csv and models/model.joblib exist" "make data && make train   (expected: roc_auc 0.802)"
fi
echo "[Course files]"
check compose_env "compose/.env.example exists (Gitea settings)" "git -C ~/mlops-lab pull"
preflight_end

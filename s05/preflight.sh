#!/usr/bin/env bash
# =============================================================================
# s05/preflight.sh — ready for session 5? Run it BEFORE class:
#     ~/mlops-lab/s05/preflight.sh                 (PROJECT=/path to check another folder)
# Checks the laptop and that ~/work/churn-mlops is at the end state of session 4:
# data v2 tracked with DVC, remote 'storage' on SeaweedFS, tag v0.2.0.
# Exit code: 0 = ready, 1 = something to fix. Read-only (runs "dvc status").
# =============================================================================
SESSION=05
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../scripts/preflight-lib.sh"
preflight_begin

s04_dvc()     { pinned 'dvc\[s3\]' && tracked .dvc/config .dvcignore && grep -q 'remote = storage' .dvc/config; }
s04_local()   { grep -q access_key_id .dvc/config.local 2>/dev/null && grep -q secret_access_key .dvc/config.local; }
s04_pointer() { tracked data/raw/churn.csv.dvc && [ -z "$(git ls-files data/raw/churn.csv)" ]; }
s04_data()    { [ -f data/raw/churn.csv ]; }
s04_status()  { uv run dvc status 2>&1 | grep -q "Data and pipelines are up to date"; }

if project_begin "end of session 4"; then
  soft  on_main     "on branch main"                                     "git switch main && git pull"
  check s04_dvc     "dvc[s3] pinned; .dvc/config committed with default remote 'storage'" "s04/README.md, step 2: uv add --dev \"dvc[s3]==3.67.1\" ; uv run dvc init ; dvc remote add -d storage s3://dvc/store"
  check s04_local   "S3 keys in .dvc/config.local"                       "uv run dvc remote modify --local storage access_key_id \"\$AWS_ACCESS_KEY_ID\"   (and secret_access_key)"
  check s04_pointer "data/raw/churn.csv.dvc committed; churn.csv itself NOT in Git" "uv run dvc add data/raw/churn.csv ; git add data/raw/churn.csv.dvc data/raw/.gitignore"
  check_tag v0.2.0 "session 4" s04
  soft  s04_data    "data/raw/churn.csv exists in the working folder"    "uv run dvc pull"
fi
echo "[Lab services]"
svc_s3
[ "$IN_PROJECT" = yes ] && check s04_status "dvc status: Data and pipelines are up to date" "uv run dvc checkout   (or: uv run dvc pull)"
svc_gitea
preflight_end

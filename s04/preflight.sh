#!/usr/bin/env bash
# =============================================================================
# s04/preflight.sh — ready for session 4? Run it BEFORE class:
#     ~/mlops-lab/s04/preflight.sh                 (PROJECT=/path to check another folder)
# Checks the laptop and that ~/work/churn-mlops is at the end state of session 3:
# branch main, .env with the S3 keys, awscli, SeaweedFS up with buckets dvc + mlflow.
# Exit code: 0 = ready, 1 = something to fix. Read-only.
# =============================================================================
SESSION=04
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../scripts/preflight-lib.sh"
preflight_begin

s03_keys()    { [ -f .env ] && for k in S3_ENDPOINT_URL AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION; do
                  V=$(envval $k); [ -n "$V" ] && [ "$V" != "CHANGE_ME" ] || return 1; done; }
s03_envfiles(){ tracked .env.example && [ -z "$(git ls-files .env)" ] && git check-ignore -q .env; }
s03_awscli()  { pinned awscli; }
s03_data()    { [ -f data/raw/churn.csv ]; }
# Bucket listing needs the project's own aws (no download, no uv sync). Skipped when it is missing.
s03_buckets() { [ -x .venv/bin/aws ] || return 1
                LS=$(AWS_ACCESS_KEY_ID="$(envval AWS_ACCESS_KEY_ID)" AWS_SECRET_ACCESS_KEY="$(envval AWS_SECRET_ACCESS_KEY)" \
                     AWS_DEFAULT_REGION="$(envval AWS_DEFAULT_REGION)" .venv/bin/aws --cli-connect-timeout 5 \
                     --endpoint-url "$(s3_url)" s3 ls 2>/dev/null) \
                  && echo "$LS" | grep -qE '[[:space:]]dvc$' && echo "$LS" | grep -qE '[[:space:]]mlflow$'; }

if project_begin "end of session 3"; then
  soft  on_main      "on branch main"                                   "git switch main && git pull"
  check origin_gitea "remote origin points to Gitea (localhost:3000)"   "git remote -v   (s02/README.md)"
  check s03_keys     ".env has S3_ENDPOINT_URL and the 3 AWS_ values (not CHANGE_ME)" "cp .env.example .env and fill in the keys from ~/mlops-lab/compose/.env (s03/README.md, step 4)"
  check s03_envfiles ".env.example is committed; .env is ignored and NOT committed" "no .env.example in Git: finish s03/README.md step 4 + 5 (create it, commit, PR). If .env itself is in Git: git rm --cached .env"
  check s03_awscli   "awscli pinned in pyproject.toml"                   "uv add --dev awscli==1.46.1"
  soft  s03_data     "data/raw/churn.csv exists"                         "make data"
fi
echo "[Lab services]"
svc_s3
[ "$IN_PROJECT" = yes ] && soft s03_buckets "buckets dvc and mlflow exist in SeaweedFS" \
  "set -a; source .env; set +a ; uv run aws --endpoint-url \$S3_ENDPOINT_URL s3 mb s3://dvc   (and s3://mlflow; s03/README.md, step 4)"
svc_gitea
preflight_end

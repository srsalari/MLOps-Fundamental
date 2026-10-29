#!/usr/bin/env bash
# =============================================================================
# verify.sh — checks the Definition of Done of a session on the student project.
# Usage:   ~/mlops-lab/scripts/verify.sh s01        (run inside ~/work/churn-mlops)
#          PROJECT=/path/to/project ~/mlops-lab/scripts/verify.sh s05
#          S3_ENDPOINT_URL=http://localhost:8333 ~/mlops-lab/scripts/verify.sh s03   (s03 reads the keys from the project .env)
#          MLFLOW_TRACKING_URI=http://localhost:5050 ~/mlops-lab/scripts/verify.sh s06   (s06-s08 read the MLflow server)
#          API_URL=http://localhost:8000 ~/mlops-lab/scripts/verify.sh s08   (the API must be running: make serve)
#          IMAGE_API_URL=http://localhost:8001 REGISTRY_URL=http://localhost:5001 ~/mlops-lab/scripts/verify.sh s09   (container running: make run-image)
#          VM_URL=http://localhost:8090 VM_SSH_PORT=2223 ~/mlops-lab/scripts/verify.sh s10   (practice VM running: make vm-up && make deploy)
#          KCTX=kind-mlops ~/mlops-lab/scripts/verify.sh s11   (cluster up: make k8s-up && make k8s-deploy)
#          INGRESS_PORT=8080 ~/mlops-lab/scripts/verify.sh s12   (Traefik + the Helm release installed: make ingress-up && make helm-deploy)
#          PROM_URL=http://localhost:9090 GRAFANA_URL=http://localhost:3001 ~/mlops-lab/scripts/verify.sh s13   (CI ran on Gitea, make mon-up, make load, make drift)
#          (s13 reads the Gitea API (the Actions API needs a login): it asks for your Gitea user and password in the terminal (the password is not shown or stored);
#           without a terminal use GITEA_USER and GITEA_PASSWORD, or GITEA_STUDENT_USER/GITEA_STUDENT_PASSWORD in ~/mlops-lab/compose/.env)
#          TAG=1.0.0 ~/mlops-lab/scripts/verify.sh s14   (run in ~/work/churn-clean after the release: image, Helm release, docs, readiness score)
#          (s14 runs scripts/readiness_check.sh of the project; QUICK=1 skips pytest and Trivy; the score must be 80 or more)
# Exit code 0 = all checks passed, 1 = at least one FAIL, 2 = usage error.
# It only reads the project; it runs "make train" (s01) and the API tests (s08).
# =============================================================================
set -uo pipefail
SESSION="${1:-}"
PROJECT="${PROJECT:-$PWD}"
PASSES=0; FAILS=0
pass() { printf '[\033[32mPASS\033[0m] %s\n' "$*"; PASSES=$((PASSES+1)); }
fail() { printf '[\033[31mFAIL\033[0m] %s\n' "$1"; [ -n "${2:-}" ] && printf '       -> %s\n' "$2"; FAILS=$((FAILS+1)); }
check() { if "$1"; then pass "$2"; else fail "$2" "${3:-}"; fi; }

usage() { echo "usage: verify.sh s01|s02|s03|s04|s05|s06|s07|s08|s09|s10|s11|s12|s13|s14   (run it inside your project folder, e.g. ~/work/churn-mlops)"; exit 2; }
[ -n "$SESSION" ] || usage
cd "$PROJECT" 2>/dev/null || { echo "project folder not found: $PROJECT"; exit 2; }
if [ ! -f pyproject.toml ] || ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "This is not the course project (no pyproject.toml or not a Git repo): $PWD"
  echo "cd ~/work/churn-mlops   and run verify.sh again."
  exit 2
fi
export GIT_TERMINAL_PROMPT=0   # never hang on a password prompt

# ---------------------------------------------------------------- session 1 --
s01_files()   { for f in src/churn/train.py scripts/make_dataset.py configs/params.yaml Makefile uv.lock README.md; do [ -f "$f" ] || return 1; done; }
s01_commit()  { git rev-parse --verify -q HEAD >/dev/null; }
s01_ignored() { [ -z "$(git ls-files data models metrics.json .env .venv 2>/dev/null)" ]; }
s01_train()   { OUT1=$(make -s train 2>/dev/null | tail -1); OUT2=$(make -s train 2>/dev/null | tail -1)
                echo "$OUT1" | grep -q "roc_auc" && [ "$OUT1" = "$OUT2" ]; }
s01_model()   { [ -f models/model.joblib ] && [ -f metrics.json ] && [ -f data/raw/churn.csv ]; }

verify_s01() {
  check s01_files   "project skeleton: src/ scripts/ configs/ Makefile uv.lock README" "copy the starter files again (s01/README.md, step 3)"
  check s01_commit  "at least one commit exists"                                      "git add . && git commit -m \"feat: project skeleton + baseline training\""
  check s01_ignored "data, model and metrics are NOT tracked by Git"                  "check .gitignore, then: git rm -r --cached data models metrics.json"
  check s01_model   "data/raw/churn.csv, models/model.joblib and metrics.json exist"  "make data && make train"
  check s01_train   "make train runs and two runs give the same metrics"              "run: make train   and read the error"
  [ -n "${OUT1:-}" ] && printf '       metrics: %s\n' "$OUT1"
}

# ---------------------------------------------------------------- session 2 --
s02_remote()  { URL=$(git remote get-url origin 2>/dev/null) || return 1
                echo "$URL" | grep -q "localhost:3000" && git ls-remote --heads origin main 2>/dev/null | grep -q "refs/heads/main"; }
s02_ruff()    { uv run ruff check -q . >/dev/null 2>&1 && uv run ruff format --check -q . >/dev/null 2>&1; }
s02_pytest()  { PYT=$(uv run pytest -q 2>&1 | tail -1); N=$(echo "$PYT" | sed -n 's/^\([0-9][0-9]*\) passed.*/\1/p')
                [ -n "$N" ] && [ "$N" -ge 4 ] && ! echo "$PYT" | grep -q "failed"; }
s02_hooks()   { H=$(git rev-parse --git-path hooks)
                [ -f .pre-commit-config.yaml ] && [ -n "$(git ls-files .pre-commit-config.yaml)" ] \
                  && grep -q "pre-commit" "$H/pre-commit" 2>/dev/null && grep -q "pre-commit" "$H/pre-push" 2>/dev/null; }
s02_tag()     { git rev-parse -q --verify "refs/tags/v0.1.0" >/dev/null && git ls-remote --tags origin v0.1.0 2>/dev/null | grep -q "v0.1.0"; }

verify_s02() {
  check s02_remote "remote origin -> Gitea, branch main is pushed"   "git remote -v ; docker compose ps (is Gitea up?) ; git push -u origin main"
  check s02_ruff   "ruff check + ruff format are clean"              "uv run ruff check --fix . && uv run ruff format ."
  check s02_pytest "pytest: at least 4 tests passed"                 "uv run pytest -q   (did you write the 4th test?)"
  [ -n "${PYT:-}" ] && printf '       pytest: %s\n' "$PYT"
  check s02_hooks  "pre-commit hooks installed (pre-commit + pre-push) and config tracked" "uv run pre-commit install --hook-type pre-commit --hook-type pre-push"
  check s02_tag    "tag v0.1.0 exists locally and on Gitea"          "git tag -a v0.1.0 -m \"...\" && git push origin v0.1.0"
}

# ---------------------------------------------------------------- session 3 --
# Docker basics + SeaweedFS S3. Read-only: only "docker info", "aws s3 ls" and git reads.
# Keys come from the project's .env (never printed). S3_ENDPOINT_URL: env var > .env > default.
envval() { sed -n "s/^$1=//p" .env 2>/dev/null | tail -1 | tr -d '\r'; }
S3_URL="${S3_ENDPOINT_URL:-$(envval S3_ENDPOINT_URL)}"; S3_URL="${S3_URL:-http://localhost:8333}"; S3_URL="${S3_URL%/}"
# awscli is a dev dependency of the project (uv add --dev awscli): prefer its binary, else uv run
s3aws() { local B R; R=$(envval AWS_DEFAULT_REGION); if [ -x .venv/bin/aws ]; then B=.venv/bin/aws; else B="uv run aws"; fi
          AWS_ACCESS_KEY_ID="$(envval AWS_ACCESS_KEY_ID)" AWS_SECRET_ACCESS_KEY="$(envval AWS_SECRET_ACCESS_KEY)" \
          AWS_DEFAULT_REGION="${R:-us-east-1}" \
          $B --cli-connect-timeout 5 --cli-read-timeout 15 --endpoint-url "$S3_URL" s3 "$@"; }

s03_docker()   { docker info >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; }
s03_s3()       { CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$S3_URL" 2>/dev/null); [ -n "$CODE" ] && [ "$CODE" != "000" ]; }
s03_keys()     { [ -f .env ] && for k in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY; do V=$(envval $k); [ -n "$V" ] && [ "$V" != "CHANGE_ME" ] || return 1; done; }
s03_awscli()   { grep -q 'awscli==' pyproject.toml && git ls-files --error-unmatch pyproject.toml uv.lock >/dev/null 2>&1; }
s03_buckets()  { LS=$(s3aws ls 2>/dev/null) && echo "$LS" | grep -qE '[[:space:]]dvc$' && echo "$LS" | grep -qE '[[:space:]]mlflow$'; }
s03_object()   { OBJ=$(s3aws ls s3://dvc/raw/churn.csv 2>/dev/null | awk '{print $3}') && [ -n "$OBJ" ] && [ "$OBJ" -gt 0 ] \
                   && { [ ! -f data/raw/churn.csv ] || [ "$OBJ" = "$(wc -c < data/raw/churn.csv | tr -d ' ')" ]; }; }
s03_envfiles() { git ls-files --error-unmatch .env.example >/dev/null 2>&1 && grep -q 'CHANGE_ME' .env.example \
                   && [ -z "$(git ls-files .env)" ] && git check-ignore -q .env; }
s03_nosecret() { SEC=$(envval AWS_SECRET_ACCESS_KEY); [ -n "$SEC" ] && [ "$SEC" != "CHANGE_ME" ] || return 1
                 ! git grep -qF -e "$SEC" -- . 2>/dev/null && [ -z "$(git log --all --oneline -S"$SEC" 2>/dev/null)" ]; }
s03_pushed()   { URL=$(git config --get remote.origin.url 2>/dev/null) && echo "$URL" | grep -q "localhost:3000" \
                   && git show main:.env.example >/dev/null 2>&1 \
                   && REMOTE=$(git ls-remote --heads origin main 2>/dev/null | cut -f1) && [ -n "$REMOTE" ] \
                   && [ "$REMOTE" = "$(git rev-parse main 2>/dev/null)" ]; }

verify_s03() {
  check s03_docker   "Docker engine and Compose v2 answer"                              "start Docker Desktop (or: colima start), then: docker ps"
  check s03_s3       "SeaweedFS S3 answers at $S3_URL"                                  "cd ~/mlops-lab/compose && docker compose up -d seaweedfs ; docker compose ps (wait for healthy)"
  check s03_keys     ".env exists and holds real lab keys (not CHANGE_ME)"              "cp .env.example .env, then set AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY to the S3_ACCESS_KEY / S3_SECRET_KEY values of ~/mlops-lab/compose/.env"
  check s03_awscli   "awscli pinned in pyproject.toml; pyproject.toml and uv.lock tracked" "uv add --dev awscli==1.46.1"
  check s03_buckets  "buckets dvc and mlflow exist"                                     "set -a; source .env; set +a ; uv run aws --endpoint-url \$S3_ENDPOINT_URL s3 mb s3://dvc   (and s3://mlflow; README step 4)"
  check s03_object   "s3://dvc/raw/churn.csv exists and its size equals data/raw/churn.csv" "uv run aws --endpoint-url \$S3_ENDPOINT_URL s3 cp data/raw/churn.csv s3://dvc/raw/churn.csv   (make data first if the file is missing)"
  [ -n "${OBJ:-}" ] && printf '       churn.csv in S3: %s bytes\n' "$OBJ"
  check s03_envfiles ".env.example is tracked (CHANGE_ME), .env is NOT tracked and is ignored" "git rm --cached .env ; echo .env >> .gitignore ; git add .env.example"
  check s03_nosecret "the lab secret is in no tracked file and in no commit"            "real keys belong only in .env (ignored); .env.example keeps CHANGE_ME; if a key is already in a commit, tell the instructor"
  check s03_pushed   "Pull Request merged: local main == origin main (Gitea) and has .env.example" "merge the PR on Gitea, then: git switch main && git pull"
}

# ---------------------------------------------------------------- session 4 --
# Read-only: no dvc pull/checkout/push. The "in the remote" check asks DVC (python API) whether an object exists in remote 'storage'.
s04_pointer() { git ls-files --error-unmatch data/raw/churn.csv.dvc >/dev/null 2>&1 \
                  && git ls-files --error-unmatch data/raw/.gitignore >/dev/null 2>&1 \
                  && [ -z "$(git ls-files data/raw/churn.csv)" ] && git check-ignore -q data/raw/churn.csv \
                  && git diff --quiet HEAD -- data/raw/churn.csv.dvc data/raw/.gitignore; }
s04_dep()     { grep -q '"dvc\[s3\]==3.67.1"' pyproject.toml && uv run dvc --version 2>/dev/null | grep -q "^3.67.1" \
                  && git ls-files --error-unmatch .dvc/config .dvcignore pyproject.toml uv.lock >/dev/null 2>&1; }
s04_config()  { C=$(git show HEAD:.dvc/config 2>/dev/null) && [ -n "$C" ] \
                  && echo "$C" | grep -q "remote = storage" && echo "$C" | grep -q 'remote "storage"' \
                  && echo "$C" | grep -q "url = s3://dvc" && echo "$C" | grep -q "endpointurl = http" \
                  && git diff --quiet HEAD -- .dvc/config; }
s04_secret()  { SECRET=$(sed -n 's/^[[:space:]]*secret_access_key[[:space:]]*=[[:space:]]*//p' .dvc/config.local 2>/dev/null | head -1)
                [ -n "$SECRET" ] && grep -q "access_key_id" .dvc/config.local \
                  && git check-ignore -q .dvc/config.local && [ -z "$(git ls-files .dvc/config.local)" ] \
                  && ! grep -qE "secret_access_key|access_key_id" .dvc/config \
                  && ! git show HEAD:.dvc/config | grep -qE "secret_access_key|access_key_id" \
                  && [ -z "$(git grep -lF -e "$SECRET" HEAD -- 2>/dev/null)" ] \
                  && [ -z "$(git log --all --oneline -S"$SECRET" 2>/dev/null)" ]; }
s04_md5s()    { MD5_V1=$(git show data-v1:data/raw/churn.csv.dvc 2>/dev/null | sed -n 's/^- md5: //p')
                MD5_V2=$(git show data-v2:data/raw/churn.csv.dvc 2>/dev/null | sed -n 's/^- md5: //p'); }
s04_tags()    { s04_md5s; [ -n "$MD5_V1" ] && [ -n "$MD5_V2" ] && [ "$MD5_V1" != "$MD5_V2" ] \
                  && R=$(git ls-remote --tags origin data-v1 data-v2 2>/dev/null) \
                  && echo "$R" | grep -q "refs/tags/data-v1" && echo "$R" | grep -q "refs/tags/data-v2"; }
s04_inremote(){ s04_md5s; [ -n "${MD5_V1:-}" ] && [ -n "${MD5_V2:-}" ] \
                  && [ "$(uv run python - "$MD5_V1" "$MD5_V2" 2>/dev/null <<'PY'
import sys
from dvc.repo import Repo
with Repo(".") as r:
    odb = r.cloud.get_remote_odb("storage")
    print(sum(1 for m in sys.argv[1:] if odb.fs.exists(odb.oid_to_path(m))))
PY
)" = "2" ]; }
s04_sync()    { uv run dvc status 2>&1 | grep -q "Data and pipelines are up to date" \
                  && uv run dvc status -c 2>&1 | grep -q "in sync"; }
s04_merged()  { s04_md5s; RM=$(git ls-remote origin refs/heads/main 2>/dev/null | cut -f1) && [ -n "$RM" ] \
                  && git cat-file -e "$RM^{commit}" 2>/dev/null \
                  && [ "$(git show "$RM:data/raw/churn.csv.dvc" 2>/dev/null | sed -n 's/^- md5: //p')" = "${MD5_V2:-x}" ] \
                  && git show "$RM:.dvc/config" 2>/dev/null | grep -q 'remote "storage"'; }
s04_tag()     { git rev-parse -q --verify "refs/tags/v0.2.0" >/dev/null && git ls-remote --tags origin v0.2.0 2>/dev/null | grep -q "v0.2.0"; }

verify_s04() {
  check s04_pointer  "data/raw/churn.csv.dvc and data/raw/.gitignore are committed; churn.csv itself is NOT in Git" "uv run dvc add data/raw/churn.csv ; git add data/raw/.gitignore data/raw/churn.csv.dvc ; (if dvc add fails: remove the 'data/' line from .gitignore)"
  check s04_dep      "dvc[s3]==3.67.1 pinned in pyproject.toml; .dvc/config and uv.lock committed" "uv add --dev \"dvc[s3]==3.67.1\" ; uv run dvc init ; git add .dvc .dvcignore pyproject.toml uv.lock && git commit"
  check s04_config   ".dvc/config (committed): default remote 'storage' -> s3://dvc/..., with endpointurl" "uv run dvc remote add -d storage s3://dvc/store ; uv run dvc remote modify storage endpointurl \"\$S3_ENDPOINT_URL\" ; git add .dvc/config && git commit"
  check s04_secret   "keys only in .dvc/config.local (ignored); no secret in tracked files or in Git history" "uv run dvc remote modify --local storage access_key_id \"\$AWS_ACCESS_KEY_ID\" (and secret_access_key) ; if a key is in .dvc/config: uv run dvc remote modify storage --unset secret_access_key"
  check s04_tags     "tags data-v1 and data-v2 exist, point to different data, and are on Gitea" "git tag -a data-v1 -m \"dataset v1 (5000 rows)\" <commit> ; git push origin --tags   (find the commit: git log --oneline)"
  [ -n "${MD5_V1:-}" ] && printf '       data-v1 md5 %s\n       data-v2 md5 %s\n' "$MD5_V1" "${MD5_V2:-?}"
  check s04_inremote "both data versions (data-v1 and data-v2) exist in the remote 'storage'" "checkout the missing version and push it: git checkout data-v1 ; uv run dvc push ; git checkout feature/dvc-data  (or main). Is SeaweedFS up and .dvc/config.local filled in?"
  check s04_sync     "dvc status: data matches the pointer; dvc status -c: cache and remote are in sync" "uv run dvc checkout   (on the branch you want) ; uv run dvc push"
  check s04_merged   "Gitea 'main' contains the pointer of data-v2 and the remote config (PR merged)" "merge the Pull Request in Gitea, then: git switch main && git pull"
  check s04_tag      "tag v0.2.0 exists locally and on Gitea"                      "git switch main && git pull && git tag -a v0.2.0 -m \"Session 4: DVC\" && git push origin --tags"
}

# ---------------------------------------------------------------- session 5 --
s05_stages()  { L=$(uv run dvc stage list 2>/dev/null); for s in preprocess train evaluate; do echo "$L" | grep -q "^$s " || return 1; done; }
s05_tracked() { for f in dvc.yaml dvc.lock params.yaml; do git ls-files --error-unmatch "$f" >/dev/null 2>&1 || return 1; done
                git diff --quiet HEAD -- dvc.yaml dvc.lock params.yaml; }
s05_status()  { uv run dvc status 2>&1 | grep -q "Data and pipelines are up to date"; }
s05_metrics() { [ -n "$(git ls-files metrics.json)" ] \
                  && uv run python -c "import json,sys; m=json.load(open('metrics.json')); sys.exit(0 if {'roc_auc','f1'} <= set(m) else 1)" 2>/dev/null \
                  && uv run dvc metrics show >/dev/null 2>&1 && uv run dvc params diff >/dev/null 2>&1; }
s05_pushed()  { uv run dvc status --cloud 2>&1 | grep -q "in sync"; }
s05_tag()     { git rev-parse -q --verify "refs/tags/v0.3.0" >/dev/null && git ls-remote --tags origin v0.3.0 2>/dev/null | grep -q "v0.3.0"; }

verify_s05() {
  check s05_stages  "dvc.yaml has the stages preprocess, train and evaluate"       "check dvc.yaml (README step 2); uv run dvc stage list"
  check s05_tracked "dvc.yaml, dvc.lock and params.yaml are committed in Git"      "git add dvc.yaml dvc.lock params.yaml && git commit -m \"feat: dvc pipeline\""
  check s05_status  "dvc status: pipeline is up to date (nothing to re-run)"       "uv run dvc repro   then commit dvc.lock"
  check s05_metrics "metrics.json is tracked, has roc_auc and f1, dvc metrics/params work" "uv run dvc repro ; git add metrics.json (remove it from .gitignore first)"
  check s05_pushed  "dvc push done: local cache and remote 'storage' are in sync"  "uv run dvc push"
  check s05_tag     "tag v0.3.0 exists locally and on Gitea"                       "git tag -a v0.3.0 -m \"Session 5: DVC pipeline\" && git push origin v0.3.0"
}

# ---------------------------------------------------------------- session 6 --
# These checks talk to the MLflow REST API with curl + python3 (no mlflow import, so they are fast).
MLFLOW_URI="${MLFLOW_TRACKING_URI:-http://localhost:5050}"; MLFLOW_URI="${MLFLOW_URI%/}"
mlf_get()  { curl -fsS --max-time 10 "$MLFLOW_URI/$1" 2>/dev/null; }
mlf_post() { curl -fsS --max-time 10 -H 'Content-Type: application/json' -d "$2" "$MLFLOW_URI/$1" 2>/dev/null; }
jq_py()    { python3 -c "import json,sys; d=json.load(sys.stdin)
$1" 2>/dev/null; }

s06_server()  { mlf_get health | grep -q "OK"; }
s06_exp()     { EXP_ID=$(mlf_get "api/2.0/mlflow/experiments/get-by-name?experiment_name=churn" | jq_py "print(d['experiment']['experiment_id'])") \
                  && [ -n "$EXP_ID" ]; }
s06_runs()    { RUNS=$(mlf_post api/2.0/mlflow/runs/search "{\"experiment_ids\":[\"$EXP_ID\"],\"filter\":\"attributes.status = 'FINISHED'\",\"order_by\":[\"attributes.start_time DESC\"],\"max_results\":100}") \
                  && N_RUNS=$(echo "$RUNS" | jq_py "
n = 0
for r in d.get('runs', []):
    m = {x['key'] for x in r['data'].get('metrics', [])}
    p = {x['key'] for x in r['data'].get('params', [])}
    n += {'roc_auc', 'f1'} <= m and 'train.C' in p
print(n)") && [ "${N_RUNS:-0}" -ge 3 ]; }
s06_latest()  { LATEST=$(echo "$RUNS" | jq_py "print(d['runs'][0]['info']['run_id'])") && [ -n "$LATEST" ] \
                  && mlf_get "api/2.0/mlflow/artifacts/list?run_id=$LATEST" | jq_py "sys.exit(0 if any(f['path'] == 'metrics.json' for f in d.get('files', [])) else 1)" \
                  && MPATH=$(mlf_post api/2.0/mlflow/logged-models/search "{\"experiment_ids\":[\"$EXP_ID\"]}" | jq_py "
for m in d.get('models', []):
    if m['info']['source_run_id'] == '$LATEST':
        print(m['info']['artifact_uri'].split(':/', 1)[1].lstrip('/'))
        break") && [ -n "$MPATH" ] \
                  && mlf_get "api/2.0/mlflow-artifacts/artifacts?path=$MPATH" | jq_py "sys.exit(0 if any(f['path'] == 'MLmodel' for f in d.get('files', [])) else 1)"; }
s06_code()    { grep -q '"mlflow==' pyproject.toml && grep -q "mlflow" src/churn/evaluate.py \
                  && for f in pyproject.toml uv.lock dvc.lock src/churn/evaluate.py; do git ls-files --error-unmatch "$f" >/dev/null 2>&1 || return 1; done \
                  && git diff --quiet HEAD -- pyproject.toml uv.lock dvc.lock src/churn/evaluate.py; }
s06_tag()     { git rev-parse -q --verify "refs/tags/v0.4.0" >/dev/null && git ls-remote --tags origin v0.4.0 2>/dev/null | grep -q "v0.4.0"; }

verify_s06() {
  check s06_server "MLflow server answers at $MLFLOW_URI"                          "cd ~/mlops-lab/compose && docker compose up -d seaweedfs mlflow ; curl $MLFLOW_URI/health"
  check s06_exp    "experiment 'churn' exists"                                     "uv run dvc repro   (needs at least one run), or: uv run dvc repro --force --single-item evaluate"
  check s06_runs   "at least 3 finished runs with roc_auc, f1 and train.C"         "uv run dvc exp run -S train.C=0.01   (restore params.yaml between experiments, README step 4)"
  [ -n "${N_RUNS:-}" ] && printf '       runs with metrics: %s\n' "$N_RUNS"
  check s06_latest "latest run has metrics.json and a model on the artifact store (S3)" "check the artifact store: docker compose logs mlflow ; bucket mlflow exists? (README troubleshooting)"
  check s06_code   "mlflow pinned in pyproject.toml; evaluate.py, uv.lock and dvc.lock committed" "git add pyproject.toml uv.lock dvc.lock src/churn/evaluate.py tests scripts Makefile && git commit"
  check s06_tag    "tag v0.4.0 exists locally and on Gitea"                        "git tag -a v0.4.0 -m \"Session 6: MLflow tracking\" && git push origin v0.4.0"
}

# ---------------------------------------------------------------- session 7 --
# Registry checks over the same REST helpers: registered model churn, aliases, gate tags.
s07_versions() { VERS=$(curl -fsS --max-time 10 -G "$MLFLOW_URI/api/2.0/mlflow/model-versions/search" --data-urlencode "filter=name='churn'" 2>/dev/null) \
                   && N_VERS=$(echo "$VERS" | jq_py "print(len(d.get('model_versions', [])))") && [ "${N_VERS:-0}" -ge 2 ]; }
s07_champion() { CHAMP=$(mlf_get "api/2.0/mlflow/registered-models/alias?name=churn&alias=champion") \
                   && CHAMP_INFO=$(echo "$CHAMP" | jq_py "
v = d['model_version']
tags = {t['key']: t['value'] for t in v.get('tags', [])}
print(f\"       @champion = version {v['version']}  roc_auc {tags.get('roc_auc')}  f1 {tags.get('f1')}\")
sys.exit(0 if tags.get('gate') == 'passed' and v.get('description') else 1)"); }
s07_gate()     { [ -n "${VERS:-}" ] && echo "$VERS" | jq_py "
sys.exit(0 if any(t['key'] == 'gate' and t['value'] == 'failed' for v in d.get('model_versions', []) for t in v.get('tags', [])) else 1)"; }
s07_files()    { MID=$(echo "$CHAMP" | jq_py "print(d['model_version']['source'].split('models:/', 1)[1])") && [ -n "$MID" ] \
                   && MPATH=$(mlf_get "api/2.0/mlflow/logged-models/$MID" | jq_py "print(d['model']['info']['artifact_uri'].split(':/', 1)[1].lstrip('/'))") && [ -n "$MPATH" ] \
                   && mlf_get "api/2.0/mlflow-artifacts/artifacts?path=$MPATH" | jq_py "sys.exit(0 if any(f['path'] == 'MLmodel' for f in d.get('files', [])) else 1)" \
                   && grep -q '^MLFLOW_ENABLE_PROXY_MULTIPART_DOWNLOAD=false' .env 2>/dev/null; }
s07_code()     { for f in src/churn/registry.py scripts/predict_champion.py tests/test_registry.py params.yaml Makefile; do git ls-files --error-unmatch "$f" >/dev/null 2>&1 || return 1; done \
                   && git show HEAD:params.yaml 2>/dev/null | grep -q "^gate:" && grep -q "^promote:" Makefile \
                   && git diff --quiet HEAD -- src/churn/registry.py params.yaml Makefile; }
s07_tag()      { git rev-parse -q --verify "refs/tags/v0.5.0" >/dev/null && git ls-remote --tags origin v0.5.0 2>/dev/null | grep -q "v0.5.0"; }

verify_s07() {
  check s06_server   "MLflow server answers at $MLFLOW_URI"                        "cd ~/mlops-lab/compose && docker compose up -d seaweedfs mlflow ; curl $MLFLOW_URI/health"
  check s07_versions "registered model 'churn' has at least 2 versions"           "make runs ; make register RUN=<run id>   (README step 2)"
  [ -n "${N_VERS:-}" ] && printf '       versions: %s\n' "$N_VERS"
  check s07_champion "alias @champion exists, passed the gate and has a release note" "make promote   (README step 3)"
  [ -n "${CHAMP_INFO:-}" ] && echo "$CHAMP_INFO"
  check s07_gate     "the gate blocked at least one version (tag gate=failed)"    "register the weak model C=0.0001 and run make promote   (README step 3)"
  check s07_files    "champion model files on the artifact store; .env has MLFLOW_ENABLE_PROXY_MULTIPART_DOWNLOAD=false" "echo MLFLOW_ENABLE_PROXY_MULTIPART_DOWNLOAD=false >> .env ; make predict"
  check s07_code     "registry.py, predict_champion.py, tests and params.yaml (gate) committed" "git add src scripts tests params.yaml Makefile && git commit"
  check s07_tag      "tag v0.5.0 exists locally and on Gitea"                      "git tag -a v0.5.0 -m \"Session 7: model registry\" && git push origin v0.5.0"
}

# ---------------------------------------------------------------- session 8 --
# The API must be running in another terminal (make serve). Only GET/POST requests are sent to it.
API_URL="${API_URL:-http://localhost:8000}"; API_URL="${API_URL%/}"
SAMPLE='{"tenure_months": 3, "monthly_charges": 95.5, "contract": "month-to-month", "internet_service": "fiber", "payment_method": "card", "support_calls": 4}'
api_post() { curl -sS --max-time 10 -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' -d "$1" "$API_URL/predict" 2>/dev/null; }

s08_deps()    { for p in '"fastapi==' '"uvicorn==' '"prometheus-fastapi-instrumentator==' '"httpx2=='; do grep -q "$p" pyproject.toml || return 1; done; }
s08_code()    { for f in src/churn/api.py scripts/check_contract.py tests/test_api.py examples/customer.json pyproject.toml uv.lock Makefile; do git ls-files --error-unmatch "$f" >/dev/null 2>&1 || return 1; done \
                  && grep -q "^serve:" Makefile && git diff --quiet HEAD -- src/churn/api.py tests/test_api.py pyproject.toml uv.lock; }
s08_tests()   { uv run pytest -q tests/test_api.py >/dev/null 2>&1; }
s08_health()  { curl -fsS --max-time 5 "$API_URL/health" 2>/dev/null | grep -q '"ok"'; }
s08_ready()   { READY=$(curl -fsS --max-time 5 "$API_URL/ready" 2>/dev/null) && API_VER=$(echo "$READY" | jq_py "print(d['model_version'])") \
                  && CHAMP_VER=$(mlf_get "api/2.0/mlflow/registered-models/alias?name=churn&alias=champion" | jq_py "print(d['model_version']['version'])") \
                  && [ -n "$API_VER" ] && [ "$API_VER" = "$CHAMP_VER" ]; }
s08_predict() { PRED=$(curl -fsS --max-time 10 -H 'Content-Type: application/json' -d "$SAMPLE" "$API_URL/predict" 2>/dev/null) \
                  && echo "$PRED" | jq_py "p = d['churn_probability']; sys.exit(0 if 0 <= p <= 1 and d['churn'] == (p > d['threshold']) else 1)" \
                  && [ "$(api_post '{"tenure_months": 3}')" = "422" ]; }
s08_metrics() { curl -fsS --max-time 5 "$API_URL/metrics" 2>/dev/null | grep -q '^churn_predictions_total{'; }
s08_tag()     { git rev-parse -q --verify "refs/tags/v0.6.0" >/dev/null && git ls-remote --tags origin v0.6.0 2>/dev/null | grep -q "v0.6.0"; }

verify_s08() {
  check s08_deps    "fastapi, uvicorn, prometheus-fastapi-instrumentator and httpx2 pinned in pyproject.toml" "uv add fastapi==0.143.2 uvicorn==0.54.0 prometheus-fastapi-instrumentator==8.1.0 && uv add --dev httpx2==2.13.1"
  check s08_code    "api.py, check_contract.py, test_api.py, examples and uv.lock committed" "git add src scripts tests examples pyproject.toml uv.lock Makefile && git commit"
  check s08_tests   "API tests pass (uv run pytest tests/test_api.py, no server needed)" "uv run pytest -q tests/test_api.py   and read the first failure"
  check s08_health  "API answers /health at $API_URL"                                "start it in another terminal: make serve"
  check s08_ready   "/ready is 200 and serves the same version as @champion"         "the API loads @champion only at startup: stop make serve (Ctrl+C) and start it again; MLflow must be up"
  [ -n "${API_VER:-}" ] && printf '       API version %s, @champion version %s\n' "$API_VER" "${CHAMP_VER:-?}"
  check s08_predict "/predict returns a probability; bad input gets HTTP 422"     "curl -s -X POST $API_URL/predict -H 'Content-Type: application/json' -d @examples/customer.json"
  [ -n "${PRED:-}" ] && printf '       %s\n' "$PRED"
  check s08_metrics "/metrics counts predictions (churn_predictions_total)"      "send one prediction first, then: curl -s $API_URL/metrics | grep churn_"
  check s08_tag     "tag v0.6.0 exists locally and on Gitea"                         "git tag -a v0.6.0 -m \"Session 8: inference API\" && git push origin v0.6.0"
}

# ---------------------------------------------------------------- session 9 --
# Reads the image with docker inspect/run, the running container, Trivy (offline DB) and the registry API.
IMAGE="${IMAGE:-churn-api:0.7.0}"
REGISTRY_URL="${REGISTRY_URL:-http://localhost:5001}"; REGISTRY_URL="${REGISTRY_URL%/}"
IMAGE_API_URL="${IMAGE_API_URL:-http://localhost:8001}"; IMAGE_API_URL="${IMAGE_API_URL%/}"
export TRIVY_CACHE_DIR="${TRIVY_CACHE_DIR:-$HOME/.cache/trivy}"

s09_files()   { for f in Dockerfile .dockerignore Makefile uv.lock; do git ls-files --error-unmatch "$f" >/dev/null 2>&1 || return 1; done; grep -q '^image:' Makefile \
                  && grep -qx '.env' .dockerignore && grep -qx '.git' .dockerignore \
                  && grep -q '^USER ' Dockerfile && grep -q '^HEALTHCHECK' Dockerfile \
                  && git diff --quiet HEAD -- Dockerfile .dockerignore Makefile uv.lock; }
s09_image()   { IMG_USER=$(docker image inspect -f '{{.Config.User}}' "$IMAGE" 2>/dev/null) || return 1
                IMG_SIZE=$(docker image inspect -f '{{.Size}}' "$IMAGE" 2>/dev/null | awk '{printf "%.2fGB", $1/1e9}')
                [ -n "$IMG_USER" ] && [ "$IMG_USER" != root ] && [ "$IMG_USER" != 0 ] \
                  && [ "$(docker image inspect -f '{{if .Config.Healthcheck}}yes{{end}}' "$IMAGE" 2>/dev/null)" = yes ]; }
s09_clean()   { docker run --rm --entrypoint sh "$IMAGE" -c 'test ! -e /app/.env && test ! -e /app/.git && test ! -e /app/data && ! command -v uv' >/dev/null 2>&1; }
s09_running() { CID=$(docker ps -q --filter "ancestor=$IMAGE" --filter health=healthy 2>/dev/null | head -1) && [ -n "$CID" ] \
                  && IMG_VER=$(curl -fsS --max-time 5 "$IMAGE_API_URL/ready" 2>/dev/null | jq_py "print(d['model_version'])") \
                  && CHAMP_VER=$(mlf_get "api/2.0/mlflow/registered-models/alias?name=churn&alias=champion" | jq_py "print(d['model_version']['version'])") \
                  && [ -n "$IMG_VER" ] && [ "$IMG_VER" = "$CHAMP_VER" ]; }
s09_scan()    { command -v trivy >/dev/null 2>&1 && [ -f "$TRIVY_CACHE_DIR/db/trivy.db" ] \
                  && trivy image -q --skip-db-update --offline-scan --skip-version-check --scanners vuln \
                       --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 "$IMAGE" >/dev/null 2>&1; }
s09_registry(){ REPO=${IMAGE%%:*}; TAG=${IMAGE##*:}
                curl -fsS --max-time 5 "$REGISTRY_URL/v2/$REPO/tags/list" 2>/dev/null | jq_py "sys.exit(0 if '$TAG' in (d.get('tags') or []) else 1)"; }
s09_tag()     { git rev-parse -q --verify "refs/tags/v0.7.0" >/dev/null && git ls-remote --tags origin v0.7.0 2>/dev/null | grep -q "v0.7.0"; }

verify_s09() {
  check s09_files    "Dockerfile (USER + HEALTHCHECK), .dockerignore (.env, .git), Makefile and uv.lock committed" "copy the files from ~/mlops-lab/s09 (README step 2), then git add .dockerignore Dockerfile Makefile uv.lock && git commit"
  check s09_image    "image $IMAGE exists, runs as a non-root user and has a HEALTHCHECK" "make image"
  [ -n "${IMG_USER:-}" ] && printf '       user %s, size %s\n' "$IMG_USER" "${IMG_SIZE:-?}"
  check s09_clean    "no .env, .git, data or uv inside the image"                 "check .dockerignore (README step 2) and the two stages of the Dockerfile, then make image"
  check s09_running  "a container of $IMAGE is healthy and $IMAGE_API_URL/ready serves the @champion version" "make run-image   (MLflow must be up; docker logs churn-api)"
  [ -n "${IMG_VER:-}" ] && printf '       container version %s, @champion version %s\n' "$IMG_VER" "${CHAMP_VER:-?}"
  check s09_scan     "Trivy (offline DB): no HIGH/CRITICAL finding that has a fix" "make scan   and fix what it lists (README step 4); DB missing? scripts/install-from-bundle.sh"
  check s09_registry "$IMAGE is in the local registry ($REGISTRY_URL)"            "start the registry (README step 5), then make push"
  check s09_tag      "tag v0.7.0 exists locally and on Gitea"                      "git tag -a v0.7.0 -m \"Session 9: container image\" && git push origin v0.7.0"
}

# --------------------------------------------------------------- session 10 --
# Reads the VM container, asks the VM through Ansible (ping, systemctl is-active) and calls the API through Nginx.
VM_NAME="${VM_NAME:-mlops-vm}"
VM_URL="${VM_URL:-http://localhost:8090}"; VM_URL="${VM_URL%/}"
VM_SSH_PORT="${VM_SSH_PORT:-2223}"
VM_KEY="${VM_KEY:-$HOME/.ssh/mlops_vm}"
vm_ansible() { (cd deploy && uv run ansible api -e ansible_port="$VM_SSH_PORT" --private-key "$VM_KEY" "$@") 2>/dev/null; }

s10_files()   { for f in deploy/deploy.yml deploy/ansible.cfg deploy/inventory.ini deploy/templates/churn-api.service.j2 \
                         deploy/templates/churn-api.env.j2 deploy/templates/nginx-churn-api.conf.j2 deploy/templates/churn-api.logrotate.j2 \
                         Makefile RUNBOOK.md pyproject.toml uv.lock; do git ls-files --error-unmatch "$f" >/dev/null 2>&1 || return 1; done
                grep -q '^deploy:' Makefile && grep -q '"ansible-core==' pyproject.toml && git diff --quiet HEAD -- deploy Makefile RUNBOOK.md; }
s10_runbook() { grep -qi 'rollback' RUNBOOK.md && grep -q 'systemctl' RUNBOOK.md && grep -qiE 'log' RUNBOOK.md; }
s10_vm()      { [ "$(docker inspect -f '{{.State.Running}}' "$VM_NAME" 2>/dev/null)" = true ]; }
s10_ping()    { vm_ansible -m ping | grep -q '"ping": "pong"'; }
s10_service() { OUT=$(vm_ansible -a "systemctl is-active churn-api nginx") && [ "$(echo "$OUT" | grep -cx 'active')" = 2 ] \
                  && vm_ansible -a "systemctl is-enabled churn-api" | grep -qx 'enabled'; }
s10_ready()   { HDR=$(curl -sS -D - -o /tmp/s10_ready.$$ --max-time 5 "$VM_URL/ready" 2>/dev/null) \
                  && echo "$HDR" | grep -qi '^server: nginx' \
                  && VM_VER=$(jq_py "print(d['model_version'])" < /tmp/s10_ready.$$) \
                  && CHAMP_VER=$(mlf_get "api/2.0/mlflow/registered-models/alias?name=churn&alias=champion" | jq_py "print(d['model_version']['version'])"); \
                rm -f /tmp/s10_ready.$$; [ -n "${VM_VER:-}" ] && [ "$VM_VER" = "${CHAMP_VER:-x}" ]; }
s10_tag()     { git rev-parse -q --verify "refs/tags/v0.8.0" >/dev/null && git ls-remote --tags origin v0.8.0 2>/dev/null | grep -q "v0.8.0"; }

verify_s10() {
  check s10_files   "deploy/ (playbook, ansible.cfg, inventory, 4 templates), Makefile, RUNBOOK.md committed; ansible-core pinned" "copy \$K/deploy and \$K/Makefile (README steps 1-2), write RUNBOOK.md, then git add .gitignore Makefile deploy pyproject.toml uv.lock RUNBOOK.md && git commit"
  check s10_runbook "RUNBOOK.md covers systemctl commands, logs and rollback"      "complete the RUNBOOK.md skeleton (README step 4)"
  check s10_vm      "practice VM container $VM_NAME is running"                     "make vm-up   (or: docker start $VM_NAME)"
  check s10_ping    "Ansible reaches the VM (ansible all -m ping)"                  "cd deploy && uv run ansible all -m ping   (key: make vm-up copies ~/.ssh/mlops_vm.pub into the VM)"
  check s10_service "churn-api and nginx are active on the VM; churn-api is enabled" "make deploy ; then make vm-ssh and: sudo systemctl status churn-api"
  check s10_ready   "$VM_URL/ready (through Nginx) serves the @champion version"    "make deploy   (after a rollback the VM serves an old version: roll forward with make deploy)"
  [ -n "${VM_VER:-}" ] && printf '       VM version %s, @champion version %s\n' "$VM_VER" "${CHAMP_VER:-?}"
  check s10_tag     "tag v0.8.0 exists locally and on Gitea"                        "git tag -a v0.8.0 -m \"Session 10: VM deploy with Ansible\" && git push origin v0.8.0"
}

# --------------------------------------------------------------- session 11 --
# Reads the kind cluster with kubectl (always with --context) and the node's Docker networks.
KCTX="${KCTX:-kind-mlops}"
K8S_NODE="${K8S_NODE:-mlops-control-plane}"
LAB_NETWORK="${LAB_NETWORK:-mlops-lab}"
k8s() { kubectl --context "$KCTX" -n churn "$@" 2>/dev/null; }

s11_files()   { for f in k8s/namespace.yaml k8s/configmap.yaml k8s/deployment.yaml k8s/service.yaml Makefile; do git ls-files --error-unmatch "$f" >/dev/null 2>&1 || return 1; done
                grep -q '^k8s-deploy:' Makefile && grep -q 'readinessProbe:' k8s/deployment.yaml && grep -q 'livenessProbe:' k8s/deployment.yaml \
                  && grep -q 'limits:' k8s/deployment.yaml && git diff --quiet HEAD -- k8s Makefile; }
s11_cluster() { kubectl --context "$KCTX" get nodes 2>/dev/null | grep -q ' Ready '; }
s11_network() { docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$K8S_NODE" 2>/dev/null | grep -qw "$LAB_NETWORK"; }
s11_ready()   { READY_N=$(k8s get deployment churn-api -o jsonpath='{.status.readyReplicas}') \
                  && WANT_N=$(k8s get deployment churn-api -o jsonpath='{.spec.replicas}') \
                  && [ -n "$READY_N" ] && [ "$READY_N" -ge 2 ] && [ "$READY_N" = "$WANT_N" ] \
                  && k8s get deployment churn-api -o jsonpath='{.spec.template.spec.containers[0].image}' | grep -q '^localhost:5001/churn-api:'; }
s11_endpoints(){ N_EP=$(k8s get endpointslices -l kubernetes.io/service-name=churn-api -o jsonpath='{range .items[*].endpoints[*]}{.conditions.ready}{"\n"}{end}' | grep -c '^true$'); [ "${N_EP:-0}" -ge 2 ]; }
s11_model()   { POD_VER=$(k8s exec deploy/churn-api -- python -c "import json,urllib.request;print(json.load(urllib.request.urlopen('http://127.0.0.1:8000/ready'))['model_version'])") \
                  && CHAMP_VER=$(mlf_get "api/2.0/mlflow/registered-models/alias?name=churn&alias=champion" | jq_py "print(d['model_version']['version'])") \
                  && [ -n "$POD_VER" ] && [ "$POD_VER" = "$CHAMP_VER" ]; }
s11_tag()     { git rev-parse -q --verify "refs/tags/v0.9.0" >/dev/null && git ls-remote --tags origin v0.9.0 2>/dev/null | grep -q "v0.9.0"; }

verify_s11() {
  check s11_files     "k8s/ (namespace, configmap, deployment with probes + limits, service) and Makefile committed" "cp -r \$K/k8s . and cp \$K/Makefile . (README steps 1-2), then git add k8s Makefile && git commit"
  check s11_cluster   "cluster answers on context $KCTX (node Ready)"                "make k8s-up   (Docker running? kubectl config get-contexts)"
  check s11_network   "node $K8S_NODE is connected to the Docker network $LAB_NETWORK (pods reach MLflow)" "docker network connect $LAB_NETWORK $K8S_NODE"
  check s11_ready     "deployment churn-api: all replicas (at least 2) ready, image from localhost:5001" "make k8s-deploy ; kubectl --context $KCTX -n churn get pods ; read the events (README step 3)"
  [ -n "${READY_N:-}" ] && printf '       ready replicas %s of %s\n' "$READY_N" "${WANT_N:-?}"
  check s11_endpoints "service churn-api has at least 2 ready endpoints"            "pods not ready: kubectl --context $KCTX -n churn describe pod -l app=churn-api"
  check s11_model     "pods serve the @champion version"                           "ConfigMap MODEL_URI changed? kubectl --context $KCTX apply -f k8s/configmap.yaml && kubectl --context $KCTX -n churn rollout restart deployment/churn-api"
  [ -n "${POD_VER:-}" ] && printf '       pod version %s, @champion version %s\n' "$POD_VER" "${CHAMP_VER:-?}"
  check s11_tag       "tag v0.9.0 exists locally and on Gitea"                     "git tag -a v0.9.0 -m \"Session 11: Kubernetes\" && git push origin v0.9.0"
}

# --------------------------------------------------------------- session 12 --
# Traefik (Ingress) and the Helm chart. Reads the cluster with kubectl and helm (always with
# --context / --kube-context) and calls the API through Traefik on laptop port INGRESS_PORT.
INGRESS_PORT="${INGRESS_PORT:-8080}"
RELEASE="${RELEASE:-churn-api}"
helmc() { helm --kube-context "$KCTX" "$@" 2>/dev/null; }
# route HOST PATH: GET through Traefik; retries twice (right after a scale-down Traefik may still point at a pod that is stopping)
route() { local i; for i in 1 2 3; do curl -fsS --max-time 5 "http://$1:$INGRESS_PORT$2" 2>/dev/null && return 0; sleep 2; done; return 1; }

s12_files()    { for f in Chart.yaml values.yaml values-dev.yaml values-prod.yaml templates/_helpers.tpl templates/deployment.yaml templates/service.yaml \
                          templates/configmap.yaml templates/ingress.yaml templates/NOTES.txt; do
                   git ls-files --error-unmatch "chart/churn-api/$f" >/dev/null 2>&1 || return 1; done
                 git ls-files --error-unmatch k8s/ingress.yaml Makefile >/dev/null 2>&1 \
                   && grep -q '^helm-deploy:' Makefile && git diff --quiet HEAD -- chart k8s Makefile; }
s12_lint()     { command -v helm >/dev/null 2>&1 && helmc lint chart/churn-api -f chart/churn-api/values-dev.yaml >/dev/null \
                   && helmc lint chart/churn-api -f chart/churn-api/values-prod.yaml >/dev/null; }
s12_traefik()  { helmc status traefik -n traefik -o json | grep -q '"status": *"deployed"' \
                   && [ "$(kubectl --context "$KCTX" -n traefik get pods --no-headers 2>/dev/null | grep -c ' 1/1 ')" -ge 1 ]; }
s12_release()  { helmc status "$RELEASE" -n churn -o json | grep -q '"status": *"deployed"' \
                   && helmc list -n churn -o json | grep -q '"chart": *"churn-api-' \
                   && READY_N=$(k8s get deployment churn-api -o jsonpath='{.status.readyReplicas}') \
                   && WANT_N=$(k8s get deployment churn-api -o jsonpath='{.spec.replicas}') \
                   && [ -n "$READY_N" ] && [ "$READY_N" -ge 1 ] && [ "$READY_N" = "$WANT_N" ] \
                   && [ "$(k8s get deployment churn-api -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}')" = Helm ]; }
s12_history()  { HIST=$(helmc history "$RELEASE" -n churn -o json) \
                   && { echo "$HIST" | grep -q '"description": *"Rollback to' || echo "$HIST" | grep -q '"status": *"failed"'; }; }   # Helm keeps only the last 10 revisions: the old failed one may be gone
s12_ingress()  { ING_VER=$(route churn.localhost /ready | jq_py "print(d['model_version'])") \
                   && CHAMP_VER=$(mlf_get "api/2.0/mlflow/registered-models/alias?name=churn&alias=champion" | jq_py "print(d['model_version']['version'])") \
                   && [ -n "$ING_VER" ] && [ "$ING_VER" = "$CHAMP_VER" ]; }
s12_hostroute(){ [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://other.localhost:$INGRESS_PORT/ready")" = 404 ] \
                   && [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://churn.localhost:$INGRESS_PORT/ready")" = 200 ]; }
s12_prod()     { helmc status "$RELEASE" -n churn-prod -o json | grep -q '"status": *"deployed"' \
                   && PROD_VER=$(route prod.churn.localhost /ready | jq_py "print(d['model_version'])") && [ -n "$PROD_VER" ]; }
s12_tag()      { git rev-parse -q --verify "refs/tags/v0.10.0" >/dev/null && git ls-remote --tags origin v0.10.0 2>/dev/null | grep -q "v0.10.0"; }

verify_s12() {
  check s12_files     "chart/churn-api (Chart, values, values-dev, values-prod, 4 templates, helpers, NOTES), k8s/ingress.yaml and the helm targets in Makefile are committed" "cp -r \$S/chart . and cp \$S/Makefile . (README steps 2-3), then git add chart k8s Makefile && git commit"
  check s12_lint      "helm lint passes with values-dev.yaml and values-prod.yaml"       "helm lint chart/churn-api -f chart/churn-api/values-dev.yaml   and read the [ERROR] line"
  check s12_traefik   "Traefik is installed (helm release deployed, pod 1/1) in namespace traefik" "make ingress-up   (README step 1)"
  check s12_release   "Helm release $RELEASE (chart churn-api) is deployed in namespace churn; all replicas ready; objects are managed by Helm" "make helm-deploy   (the S11 objects must be deleted first: kubectl --context $KCTX delete -f k8s/ ; README step 3)"
  [ -n "${READY_N:-}" ] && printf '       ready replicas %s of %s\n' "$READY_N" "${WANT_N:-?}"
  check s12_history   "helm history shows a rollback (or the failed upgrade)"            "do the bad upgrade and helm rollback of README step 4 (Helm keeps only the last 10 revisions)"
  check s12_ingress   "http://churn.localhost:$INGRESS_PORT/ready serves the @champion version" "Traefik running? curl -i http://churn.localhost:$INGRESS_PORT/ready ; the release may pin a model: helm get values $RELEASE -n churn"
  [ -n "${ING_VER:-}" ] && printf '       ingress version %s, @champion version %s\n' "$ING_VER" "${CHAMP_VER:-?}"
  check s12_hostroute "host-based routing: churn.localhost answers 200, an unknown host answers 404" "kubectl --context $KCTX -n churn get ingress ; the Ingress needs ingressClassName traefik"
  check s12_prod      "release $RELEASE in namespace churn-prod is deployed and prod.churn.localhost answers" "make helm-deploy STAGE=prod NS=churn-prod   (README step 4)"
  check s12_tag       "tag v0.10.0 exists locally and on Gitea"                          "git tag -a v0.10.0 -m \"Session 12: Ingress + Helm\" && git push origin v0.10.0"
}

# --------------------------------------------------------------- session 13 --
# CI on Gitea Actions, monitoring (Prometheus + Grafana) and the drift report. It reads the
# Gitea API (needs the lab account), the local registry, Prometheus and Grafana.
GITEA_URL="${GITEA_URL:-http://localhost:3000}"; GITEA_URL="${GITEA_URL%/}"
PROM_URL="${PROM_URL:-http://localhost:9090}"; PROM_URL="${PROM_URL%/}"
GRAFANA_URL="${GRAFANA_URL:-http://localhost:3001}"; GRAFANA_URL="${GRAFANA_URL%/}"
REGISTRY_URL="${REGISTRY_URL:-http://localhost:5001}"; REGISTRY_URL="${REGISTRY_URL%/}"
LABDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
labenv() { sed -n "s/^$1=//p" "$LABDIR/compose/.env" 2>/dev/null | tail -1 | tr -d '\r'; }
# gitea_api PATH: GET /api/v1/PATH with the lab account (the password is never printed)
gitea_api() { local u="$GITEA_USER" p="$GITEA_PASSWORD"
              if [ -n "$u" ] && [ -n "$p" ]; then curl -fsS --max-time 10 -u "$u:$p" "$GITEA_URL/api/v1/$1" 2>/dev/null
              else curl -fsS --max-time 10 "$GITEA_URL/api/v1/$1" 2>/dev/null; fi; }
# gitea_login: make sure we have a user and password (env, compose/.env, or ask on the terminal)
gitea_login() {
  GITEA_USER="${GITEA_USER:-$(labenv GITEA_STUDENT_USER)}"; GITEA_PASSWORD="${GITEA_PASSWORD:-$(labenv GITEA_STUDENT_PASSWORD)}"
  if [ -z "$GITEA_PASSWORD" ] && [ -t 0 ]; then
    [ -n "$GITEA_USER" ] || { read -r -p "Gitea user [student]: " GITEA_USER; GITEA_USER="${GITEA_USER:-student}"; }
    read -rs -p "Gitea password for $GITEA_USER (not shown): " GITEA_PASSWORD; echo
  fi
}
repo_path() { git remote get-url origin 2>/dev/null | sed -E 's#^.*[:/]([^/:]+/[^/]+)$#\1#; s#\.git$##'; }
# run_ok NAME EXTRA: at least one finished run of workflow NAME.yaml succeeded (EXTRA = more python conditions)
run_ok()    { gitea_api "repos/$(repo_path)/actions/runs?limit=50" \
                | jq_py "import sys
runs=[r for r in d.get('workflow_runs',[]) if r.get('path','').startswith('$1.yaml@') and r.get('status')=='completed' $2]
print('success' if any(r['conclusion']=='success' for r in runs) else 'none')" | grep -q success; }

s13_files()    { for f in .gitea/workflows/ci.yaml .gitea/workflows/ml-ci.yaml .gitea/workflows/retrain.yaml \
                          monitoring/docker-compose.yml monitoring/prometheus/prometheus.yml monitoring/prometheus/alerts.yml \
                          monitoring/grafana/provisioning/datasources/prometheus.yml monitoring/grafana/provisioning/dashboards/dashboards.yml \
                          monitoring/grafana/dashboards/churn-api.json scripts/pr_comment.py scripts/loadgen.py scripts/drift_report.py \
                          tests/test_pr_comment.py tests/test_drift_summary.py; do
                   git ls-files --error-unmatch "$f" >/dev/null 2>&1 || return 1; done
                 grep -q '^mon-up:' Makefile && git diff --quiet HEAD -- .gitea monitoring scripts tests Makefile pyproject.toml uv.lock; }
s13_offline()  { ! grep -qE '^[[:space:]]*(-[[:space:]]+)?uses:' .gitea/workflows/*.yaml; }
s13_ci_run()   { run_ok ci "and r.get('head_branch')=='main'"; }
s13_ci_image() { TAGS=$(curl -fsS --max-time 5 "$REGISTRY_URL/v2/churn-api/tags/list" 2>/dev/null) || return 1
                 for t in $(echo "$TAGS" | jq_py "print(' '.join(t for t in d['tags'] if t.startswith('ci-')))"); do
                   git merge-base --is-ancestor "${t#ci-}" HEAD 2>/dev/null && { CI_TAG=$t; return 0; }; done; return 1; }
s13_pr()       { gitea_api "repos/$(repo_path)/pulls?state=all&limit=20" | jq_py "print(' '.join(str(p['number']) for p in d))" > /tmp/.s13_prs.$$ || return 1
                 for n in $(cat /tmp/.s13_prs.$$); do
                   gitea_api "repos/$(repo_path)/issues/$n/comments" | grep -q 'metrics-diff' && { PR_N=$n; rm -f /tmp/.s13_prs.$$; return 0; }; done
                 rm -f /tmp/.s13_prs.$$; return 1; }
s13_mlci_run() { run_ok ml-ci ""; }
s13_retrain()  { run_ok retrain ""; }
s13_challenger() { CH_V=$(mlf_get "api/2.0/mlflow/registered-models/alias?name=churn&alias=challenger" | jq_py "print(d['model_version']['version'])") && [ -n "$CH_V" ]; }
s13_prom_up()  { curl -fsS --max-time 5 "$PROM_URL/api/v1/targets" 2>/dev/null \
                   | jq_py "print('ok' if any(t['labels'].get('job')=='churn-api' and t['health']=='up' for t in d['data']['activeTargets']) else 'no')" | grep -q ok; }
prom_q()       { curl -fsS --max-time 10 -G "$PROM_URL/api/v1/query" --data-urlencode "query=$1" 2>/dev/null \
                   | jq_py "r=d['data']['result']; print(r[0]['value'][1] if r else 0)"; }
s13_traffic()  { REQ=$(prom_q 'sum(max_over_time(http_requests_total{job="churn-api",handler="/predict"}[6h]))') && python3 -c "import sys; sys.exit(0 if float('${REQ:-0}')>=50 else 1)"; }
s13_5xx()      { E5=$(prom_q 'sum(max_over_time(http_requests_total{job="churn-api",status="5xx"}[6h]))') && python3 -c "import sys; sys.exit(0 if float('${E5:-0}')>=1 else 1)"; }
s13_grafana()  { curl -fsS --max-time 5 -u "admin:mlops-lab" "$GRAFANA_URL/api/dashboards/uid/churn-api-red" 2>/dev/null \
                   | jq_py "print(len(d['dashboard']['panels']))" | grep -qE '^[1-9]'; }
s13_rules()    { curl -fsS --max-time 5 "$PROM_URL/api/v1/rules" 2>/dev/null | grep -q '"name": *"ChurnApiDown"\|"name":"ChurnApiDown"'; }
s13_drift()    { grep -q 'evidently==0.7.23' pyproject.toml && grep -qE '^reports/?$' .gitignore \
                   && [ -f reports/drift-v1-v2.html ] && [ "$(wc -c < reports/drift-v1-v2.html)" -gt 500000 ] \
                   && grep -q 'tenure_months' reports/drift-v1-v2.html; }
s13_tests()    { PYT=$(uv run pytest -q 2>&1 | tail -1); N=$(echo "$PYT" | sed -n 's/^\([0-9][0-9]*\) passed.*/\1/p')
                 [ -n "$N" ] && [ "$N" -ge 26 ] && ! echo "$PYT" | grep -q "failed"; }
s13_tag()      { git rev-parse -q --verify "refs/tags/v0.11.0" >/dev/null && git ls-remote --tags origin v0.11.0 2>/dev/null | grep -q "v0.11.0"; }

verify_s13() {
  gitea_login
  check s13_files    "workflows, monitoring/ (compose, Prometheus, Grafana, dashboard), scripts, tests, Makefile and the drift dependency are committed" "cp -r \$S/.gitea \$S/monitoring . ; cp \$S/scripts/* scripts/ ; cp \$S/tests/* tests/ ; cp \$S/Makefile . (README steps 1-4), then git add -A && git commit"
  check s13_offline  "no workflow uses 'uses:' (marketplace actions need the internet; plain git and make work offline)" "replace 'uses: actions/checkout' with the git commands of s13/.gitea/workflows/ci.yaml"
  check s13_ci_run   "Gitea Actions: a run of workflow 'ci' on main finished with success" "open the repo > Actions in Gitea and read the red step (README step 1); is the runner up (make runner-up)? verify.sh needs your Gitea password: run it in a terminal, or set GITEA_USER and GITEA_PASSWORD"
  check s13_ci_image "the registry has an image churn-api:ci-<sha> built by CI from a commit that is in this branch" "the push step runs only on main: merge your commit to main and wait for the green run"
  [ -n "${CI_TAG:-}" ] && printf '       registry tag %s\n' "$CI_TAG"
  check s13_pr       "a pull request has the automatic metrics-diff comment" "make a branch that changes params.yaml, push it, open a pull request (README step 2); the ml-ci workflow must be green"
  [ -n "${PR_N:-}" ] && printf '       comment found on pull request #%s\n' "$PR_N"
  check s13_mlci_run "workflow 'ml-ci' finished with success at least once"       "Actions tab: open the red run of ml-ci and read the step that failed"
  check s13_retrain  "workflow 'retrain' ran (manual run is fine) and finished with success" "Actions > retrain > Run workflow (README step 2)"
  check s13_challenger "MLflow has the alias @challenger (the retrain registered a new version)" "make models; the retrain workflow registers it in its last step"
  [ -n "${CH_V:-}" ] && printf '       @challenger = version %s\n' "$CH_V"
  check s13_prom_up  "Prometheus scrapes the API: target churn-api is up"         "make mon-up ; make mon-status   (Prometheus $PROM_URL)"
  check s13_traffic  "Prometheus has seen at least 50 requests to /predict"       "make load RPS=5 DURATION=60"
  [ -n "${REQ:-}" ] && printf '       /predict requests seen: %s\n' "${REQ%.*}"
  check s13_5xx      "Prometheus has seen at least one 5xx error (the api-break demo)" "make api-break ; make load BAD=0.1 DURATION=30 ; make api-fix"
  check s13_grafana  "Grafana has the provisioned dashboard 'Churn API: RED metrics'" "make mon-up ; open $GRAFANA_URL (user admin, password mlops-lab)"
  check s13_rules    "Prometheus loaded the alert rule ChurnApiDown"              "check monitoring/prometheus/alerts.yml and: curl -X POST $PROM_URL/-/reload"
  check s13_drift    "evidently==0.7.23 is in the drift group, reports/ is ignored by Git, and reports/drift-v1-v2.html exists" "uv add --group drift evidently==0.7.23 ; echo reports/ >> .gitignore ; make drift (README step 4)"
  check s13_tests    "pytest passes with the new tests (26 or more)"              "uv run pytest -q   and read the error"
  check s13_tag      "tag v0.11.0 exists locally and on Gitea"                    "git tag -a v0.11.0 -m \"Session 13: CI + monitoring + drift\" && git push origin v0.11.0"
}

# --------------------------------------------------------------- session 14 --
# Capstone: the release from a clean clone. It runs the project's own scorer
# (scripts/readiness_check.sh) and checks the documents, the image tag and the tag v1.0.0.
S14_TAG="${TAG:-1.0.0}"
s14_files()   { tracked_all() { for f in "$@"; do git ls-files --error-unmatch "$f" >/dev/null 2>&1 || return 1; done; }
                tracked_all README.md RUNBOOK.md DEMO.md scripts/readiness_check.sh Makefile && grep -q '^demo-check:' Makefile \
                  && git diff --quiet HEAD -- README.md RUNBOOK.md DEMO.md scripts/readiness_check.sh Makefile; }
s14_nofill()  { ! grep -qE '<FILL|TODO' README.md RUNBOOK.md DEMO.md; }
s14_runbook() { for sec in Start Stop Restart Logs Rollback Health; do grep -qiE "^##+ .*$sec" RUNBOOK.md || return 1; done; }
s14_score()   { [ -x scripts/readiness_check.sh ] || return 1
                SCORE_OUT=$(TAG="$S14_TAG" scripts/readiness_check.sh 2>/dev/null); SC=$(echo "$SCORE_OUT" | sed -n 's/^SCORE=\([0-9]*\)\/100$/\1/p')
                [ -n "$SC" ] && [ "$SC" -ge 80 ]; }
s14_image()   { docker image inspect "churn-api:$S14_TAG" >/dev/null 2>&1 \
                  && curl -fsS --max-time 5 "${REGISTRY_URL:-http://localhost:5001}/v2/churn-api/tags/list" 2>/dev/null | grep -q "\"$S14_TAG\""; }
s14_deployed(){ DEP_IMG=$(k8s get deployment churn-api -o jsonpath='{.spec.template.spec.containers[0].image}'); echo "$DEP_IMG" | grep -q ":$S14_TAG\$"; }
s14_tag()     { git rev-parse -q --verify "refs/tags/v1.0.0" >/dev/null && git ls-remote --tags origin v1.0.0 2>/dev/null | grep -q "v1.0.0" \
                  && git merge-base --is-ancestor v1.0.0 origin/main 2>/dev/null; }

verify_s14() {
  check s14_files    "README.md, RUNBOOK.md, DEMO.md, scripts/readiness_check.sh and the Makefile (with demo-check) are committed" "cp ~/mlops-lab/s14/RUNBOOK.md ~/mlops-lab/s14/DEMO.md . ; cp ~/mlops-lab/s14/README.project.md README.md ; cp ~/mlops-lab/s14/scripts/readiness_check.sh scripts/ ; cp ~/mlops-lab/s14/Makefile . (README steps 4-5), then git add and commit"
  check s14_nofill   "no <FILL> or TODO is left in README.md, RUNBOOK.md and DEMO.md"                 "grep -n 'FILL' README.md RUNBOOK.md DEMO.md   and write your own text"
  check s14_runbook  "RUNBOOK.md has the sections Start, Stop, Restart, Logs, Rollback and Health"    "compare with ~/mlops-lab/s14/RUNBOOK.md"
  check s14_score    "readiness score is 80 or more (scripts/readiness_check.sh)"                      "scripts/readiness_check.sh and fix the failed items, biggest points first (PRODUCTION-READINESS.md)"
  [ -n "${SC:-}" ] && printf '       readiness score: %s/100   (%s)\n' "$SC" "$(echo "$SCORE_OUT" | grep -c 'FAIL') failed items, $(echo "$SCORE_OUT" | grep -c 'SKIP') skipped"
  check s14_image    "image churn-api:$S14_TAG exists locally and in the registry"                     "make image TAG=$S14_TAG && make push TAG=$S14_TAG   (README step 2; TAG=... verify.sh s14 for another tag)"
  check s14_deployed "the Helm release runs churn-api:$S14_TAG (built from the clean clone)"           "make helm-deploy STAGE=dev HELM_ARGS=\"--set image.tag=$S14_TAG\"   (README step 3)"
  [ -n "${DEP_IMG:-}" ] && printf '       deployment image: %s\n' "$DEP_IMG"
  check s14_tag      "tag v1.0.0 is on Gitea and is part of origin/main"                               "merge your release branch, then: git switch main && git pull && git tag -a v1.0.0 -m \"Capstone\" && git push origin v1.0.0"
}

case "$SESSION" in
  s01) verify_s01 ;;
  s02) verify_s02 ;;
  s03) verify_s03 ;;
  s04) verify_s04 ;;
  s05) verify_s05 ;;
  s06) verify_s06 ;;
  s07) verify_s07 ;;
  s08) verify_s08 ;;
  s09) verify_s09 ;;
  s10) verify_s10 ;;
  s11) verify_s11 ;;
  s12) verify_s12 ;;
  s13) verify_s13 ;;
  s14) verify_s14 ;;
  *)   echo "no checks defined for '$SESSION' yet (available: s01 to s14)"; exit 2 ;;
esac

TOTAL=$((PASSES+FAILS))
echo "$SESSION: $PASSES/$TOTAL checks passed   (commit $(git rev-parse --short HEAD 2>/dev/null), branch $(git branch --show-current 2>/dev/null))"
[ "$FAILS" -eq 0 ]

#!/usr/bin/env bash
# =============================================================================
# readiness_check.sh — scores the churn project against PRODUCTION-READINESS.md (100 points).
#
#   cd ~/work/churn-mlops && scripts/readiness_check.sh
#
# Every item is ONE check (a shell function below) with points, the session it belongs to,
# and a hint. A check ends in PASS (points earned), FAIL (no points, the hint tells the fix)
# or SKIP (it could not be checked, e.g. no Gitea password: no points, but it is listed;
# inside a check, "return 77" means SKIP).
# It never asks a question and never changes anything (read-only: it only reads files, Git,
# the cluster and the HTTP answers of your services).
#
# Settings (environment variables, defaults are the class values):
#   SERVICE_URL   the service through Traefik          http://churn.localhost:8080
#   MLFLOW_TRACKING_URI  from .env, else               http://localhost:5050
#   PROM_URL      http://localhost:9090      GRAFANA_URL  http://localhost:3001
#   REGISTRY_URL  http://localhost:5001      GITEA_URL    http://localhost:3000
#   KCTX          kubectl/helm context       kind-mlops
#   NS / RELEASE  namespace and Helm release churn / churn-api
#   IMAGE / TAG   image to scan (Trivy)      churn-api / 0.7.0
#   GITEA_USER, GITEA_PASSWORD   for the CI check (or GITEA_STUDENT_USER/PASSWORD in ~/mlops-lab/compose/.env)
#   QUICK=1       skip the two slow checks (pytest, Trivy): they are listed as SKIP
#
# Exit code: 0 = score 80 or more, 1 = below 80, 2 = not the course project.
# Works with bash 3.2 (macOS) and bash 5 (Ubuntu / WSL).
# =============================================================================
set -uo pipefail
PROJECT="${PROJECT:-$PWD}"
cd "$PROJECT" 2>/dev/null || { echo "project folder not found: $PROJECT"; exit 2; }
if [ ! -f pyproject.toml ] || ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "This is not the course project (no pyproject.toml or not a Git repo): $PWD"; exit 2
fi
export GIT_TERMINAL_PROMPT=0
LABDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

SERVICE_URL="${SERVICE_URL:-http://churn.localhost:8080}"; SERVICE_URL="${SERVICE_URL%/}"
PROM_URL="${PROM_URL:-http://localhost:9090}"; PROM_URL="${PROM_URL%/}"
GRAFANA_URL="${GRAFANA_URL:-http://localhost:3001}"; GRAFANA_URL="${GRAFANA_URL%/}"
REGISTRY_URL="${REGISTRY_URL:-http://localhost:5001}"; REGISTRY_URL="${REGISTRY_URL%/}"
GITEA_URL="${GITEA_URL:-http://localhost:3000}"; GITEA_URL="${GITEA_URL%/}"
KCTX="${KCTX:-kind-mlops}"; NS="${NS:-churn}"; RELEASE="${RELEASE:-churn-api}"
IMAGE="${IMAGE:-churn-api}"; TAG="${TAG:-0.7.0}"
QUICK="${QUICK:-0}"

envval() { sed -n "s/^$1=//p" .env 2>/dev/null | tail -1 | tr -d '\r'; }
MLFLOW_URI="${MLFLOW_TRACKING_URI:-$(envval MLFLOW_TRACKING_URI)}"; MLFLOW_URI="${MLFLOW_URI:-http://localhost:5050}"; MLFLOW_URI="${MLFLOW_URI%/}"
jq_py()   { python3 -c "import json,sys; d=json.load(sys.stdin)
$1" 2>/dev/null; }
mlf_get() { curl -fsS --max-time 10 "$MLFLOW_URI/$1" 2>/dev/null; }
tracked() { for f in "$@"; do git ls-files --error-unmatch "$f" >/dev/null 2>&1 || return 1; done; }
have()    { command -v "$1" >/dev/null 2>&1; }
HELM()    { helm --kube-context "$KCTX" "$@"; }
NOTE=""   # a SKIP reason or an extra detail, set by a check

# ------------------------------------------------------------------ pillar A --
# A. Reproducibility (20)
c_pinned()   { tracked uv.lock pyproject.toml || return 1
               python3 - <<'EOF'
import re, sys, tomllib
t = tomllib.load(open("pyproject.toml", "rb"))
deps = list(t["project"].get("dependencies", []))
for g in t.get("dependency-groups", {}).values():
    deps += [d for d in g if isinstance(d, str)]
bad = [d for d in deps if "==" not in d]
if bad:
    print("not pinned with ==:", ", ".join(bad)); sys.exit(1)
EOF
}
c_secrets()  { tracked .env.example && [ -z "$(git ls-files .env)" ] && git check-ignore -q .env 2>/dev/null || return 1
               local sec; sec=$(envval AWS_SECRET_ACCESS_KEY)
               [ -z "$sec" ] || [ "$sec" = CHANGE_ME ] || { ! git grep -qF -e "$sec" 2>/dev/null && [ -z "$(git log --all --oneline -S"$sec" 2>/dev/null | head -1)" ]; }; }
c_lint()     { have uv && uv run ruff check -q . >/dev/null 2>&1 && uv run ruff format --check -q . >/dev/null 2>&1; }
c_tests()    { [ "$QUICK" = 1 ] && { NOTE="QUICK=1"; return 77; }
               have uv || return 1
               local out n; out=$(uv run pytest -q 2>&1 | tail -1); n=$(echo "$out" | sed -n 's/^\([0-9][0-9]*\) passed.*/\1/p')
               NOTE="$out"; [ -n "$n" ] && [ "$n" -ge 20 ] && ! echo "$out" | grep -q failed; }
c_dvcdata()  { tracked data/raw/churn.csv.dvc && [ -z "$(git ls-files data/raw/churn.csv)" ] && git check-ignore -q data/raw/churn.csv 2>/dev/null \
                 && grep -q 's3://' .dvc/config \
                 && git rev-parse -q --verify refs/tags/data-v1 >/dev/null && git rev-parse -q --verify refs/tags/data-v2 >/dev/null; }
c_dvcpipe()  { have uv && [ "$(grep -cE '^  [a-z_]+:$' dvc.yaml)" -ge 3 ] && tracked dvc.lock \
                 && uv run dvc status 2>&1 | grep -q 'up to date'; }
c_tags()     { local n; n=$(git tag -l 'v[0-9]*' | wc -l | tr -d ' '); NOTE="$n version tags"
               [ "$n" -ge 5 ] && git remote get-url origin >/dev/null 2>&1 && [ "$(git ls-remote --tags origin 'v[0-9]*' 2>/dev/null | grep -vc '\^{}')" -ge 5 ]; }

# ------------------------------------------------------------------ pillar B --
# B. Model lifecycle (12)
c_mlruns()   { curl -fsS --max-time 5 "$MLFLOW_URI/health" 2>/dev/null | grep -q OK || return 1
               curl -fsS --max-time 10 -X POST -H 'Content-Type: application/json' "$MLFLOW_URI/api/2.0/mlflow/runs/search" \
                 -d '{"experiment_ids":["1"],"max_results":5}' 2>/dev/null | grep -q '"run_id"'; }
c_champion() { local v; v=$(mlf_get "api/2.0/mlflow/registered-models/alias?name=churn&alias=champion" | jq_py "print(d['model_version']['version'])") || return 1
               [ -n "$v" ] && NOTE="@champion = version $v"; }
c_gate()     { mlf_get "api/2.0/mlflow/registered-models/alias?name=churn&alias=champion" | jq_py "
t={x['key']:x['value'] for x in d['model_version'].get('tags',[])}
import sys
sys.exit(0 if t.get('gate')=='passed' and t.get('data_md5') else 1)"; }

# ------------------------------------------------------------------ pillar C --
# C. Serving and image (18)
c_service()  { local r p b; r=$(curl -fsS --max-time 5 "$SERVICE_URL/ready" 2>/dev/null) || return 1
               echo "$r" | grep -q model_version || return 1
               p=$(curl -fsS --max-time 10 -X POST "$SERVICE_URL/predict" -H 'Content-Type: application/json' -d @examples/customer.json 2>/dev/null) || return 1
               echo "$p" | grep -q churn_probability || return 1
               b=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -X POST "$SERVICE_URL/predict" -H 'Content-Type: application/json' -d @examples/bad_customer.json 2>/dev/null)
               NOTE="$r"; [ "$b" = 422 ]; }
c_metrics()  { curl -fsS --max-time 5 "$SERVICE_URL/metrics" 2>/dev/null | grep -q '^http_requests_total'; }
c_dockerfile() { [ "$(grep -c '^FROM ' Dockerfile)" -ge 2 ] && grep -q '^USER ' Dockerfile && grep -q '^HEALTHCHECK' Dockerfile; }
c_dockerignore() { grep -qE '^\.env' .dockerignore 2>/dev/null && grep -qE '^\.git$' .dockerignore 2>/dev/null; }
c_trivy()    { [ "$QUICK" = 1 ] && { NOTE="QUICK=1"; return 77; }
               have trivy && docker image inspect "$IMAGE:$TAG" >/dev/null 2>&1 || { NOTE="image $IMAGE:$TAG or trivy missing"; return 1; }
               make -s scan IMAGE="$IMAGE" TAG="$TAG" >/dev/null 2>&1; }
c_registry() { curl -fsS --max-time 5 "$REGISTRY_URL/v2/churn-api/tags/list" 2>/dev/null | jq_py "
import sys
sys.exit(0 if d.get('tags') else 1)"; }
c_apitests() { tracked tests/test_api.py && [ "$(grep -c '^def test_' tests/test_api.py)" -ge 3 ]; }

# ------------------------------------------------------------------ pillar D --
# D. Deployment (20)
c_ansible()  { tracked deploy/deploy.yml deploy/inventory.ini && have uv && (cd deploy && uv run ansible-playbook --syntax-check deploy.yml >/dev/null 2>&1); }
c_chart()    { have helm || return 1
               local f out
               for f in dev prod; do
                 out=$(helm template x chart/churn-api -f "chart/churn-api/values-$f.yaml" 2>/dev/null) || return 1
                 for k in readinessProbe livenessProbe limits requests; do echo "$out" | grep -q "$k" || { NOTE="$f: no $k"; return 1; }; done
               done; }
c_helmlint() { have helm && helm lint chart/churn-api -f chart/churn-api/values-dev.yaml >/dev/null 2>&1 && helm lint chart/churn-api -f chart/churn-api/values-prod.yaml >/dev/null 2>&1; }
c_prodvals() { python3 - <<'EOF'
import re, sys
t = open("chart/churn-api/values-prod.yaml").read()
m = re.search(r"^replicaCount:\s*(\d+)", t, re.M)
u = re.search(r"modelUri:\s*[\"']?(\S+?)[\"']?\s*$", t, re.M)
ok = bool(m) and int(m.group(1)) >= 2 and bool(u) and "@" not in u.group(1)
sys.exit(0 if ok else 1)
EOF
}
c_release()  { have helm && have kubectl || return 1
               HELM status "$RELEASE" -n "$NS" -o json 2>/dev/null | grep -q '"status": *"deployed"' || return 1
               local r w; r=$(kubectl --context "$KCTX" -n "$NS" get deploy churn-api -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
               w=$(kubectl --context "$KCTX" -n "$NS" get deploy churn-api -o jsonpath='{.spec.replicas}' 2>/dev/null)
               NOTE="ready $r of $w"; [ -n "$r" ] && [ "$r" = "$w" ]; }
c_routing()  { local host port base; base="${SERVICE_URL#http://}"; port="${base##*:}"
               [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$SERVICE_URL/ready")" = 200 ] \
                 && [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://other.localhost:$port/ready")" = 404 ]; }
c_rollback() { grep -q '^helm-rollback:' Makefile && grep -q '^rollback:' Makefile; }

# ------------------------------------------------------------------ pillar E --
# E. Automation and observability (14)
c_cifiles()  { tracked .gitea/workflows/ci.yaml .gitea/workflows/ml-ci.yaml .gitea/workflows/retrain.yaml \
                 && grep -q 'make lint' .gitea/workflows/ci.yaml && grep -q 'make test' .gitea/workflows/ci.yaml && grep -q 'make scan' .gitea/workflows/ci.yaml \
                 && ! grep -qE '^[[:space:]]*(-[[:space:]]+)?uses:' .gitea/workflows/*.yaml; }
gitea_creds() { GU="${GITEA_USER:-$(sed -n 's/^GITEA_STUDENT_USER=//p' "$HOME/mlops-lab/compose/.env" 2>/dev/null | tail -1)}"
                GP="${GITEA_PASSWORD:-$(sed -n 's/^GITEA_STUDENT_PASSWORD=//p' "$HOME/mlops-lab/compose/.env" 2>/dev/null | tail -1)}"
                [ -n "$GU" ] && [ -n "$GP" ]; }
c_cirun()    { gitea_creds || { NOTE="no Gitea login: set GITEA_USER and GITEA_PASSWORD"; return 77; }
               local rp; rp=$(git remote get-url origin 2>/dev/null | sed -E 's#^.*[:/]([^/:]+/[^/]+)$#\1#; s#\.git$##')
               curl -fsS --max-time 10 -u "$GU:$GP" "$GITEA_URL/api/v1/repos/$rp/actions/runs?limit=50" 2>/dev/null | jq_py "
import sys
runs=[r for r in d.get('workflow_runs',[]) if r.get('path','').startswith('ci.yaml@') and r.get('head_branch')=='main' and r.get('status')=='completed']
sys.exit(0 if any(r['conclusion']=='success' for r in runs) else 1)"; }
c_prom()     { curl -fsS --max-time 5 "$PROM_URL/api/v1/targets" 2>/dev/null \
                 | jq_py "import sys; sys.exit(0 if any(t['labels'].get('job')=='churn-api' and t['health']=='up' for t in d['data']['activeTargets']) else 1)" \
               && curl -fsS --max-time 5 "$PROM_URL/api/v1/rules" 2>/dev/null | grep -q 'ChurnApiDown'; }
c_grafana()  { curl -fsS --max-time 5 -u "admin:mlops-lab" "$GRAFANA_URL/api/dashboards/uid/churn-api-red" 2>/dev/null \
                 | jq_py "import sys; sys.exit(0 if len(d['dashboard']['panels'])>=1 else 1)"; }
c_drift()    { grep -q 'evidently==' pyproject.toml && tracked scripts/drift_report.py \
                 && [ -f reports/drift-v1-v2.html ] && [ "$(wc -c < reports/drift-v1-v2.html)" -gt 500000 ]; }

# ------------------------------------------------------------------ pillar F --
# F. Documentation and delivery (16)
c_readme()   { [ "$(grep -c . README.md 2>/dev/null)" -ge 20 ] && grep -qi '^#.*quick *start' README.md && grep -qi '^#.*architecture' README.md \
                 && ! grep -qE 'TODO|<FILL' README.md; }
c_runbook()  { [ -f RUNBOOK.md ] || return 1
               local s; for s in 'Start' 'Stop' 'Restart' 'Logs' 'Rollback' 'Health'; do
                 grep -qiE "^##+ .*$s" RUNBOOK.md || { NOTE="no section: $s"; return 1; }; done
               [ "$(grep -c '^```' RUNBOOK.md)" -ge 12 ] && ! grep -qE 'TODO|<FILL' RUNBOOK.md; }
c_demo()     { [ -f DEMO.md ] && [ "$(grep -cE '^##+ .*[0-9]+:[0-9]{2}' DEMO.md)" -ge 5 ] && ! grep -qE 'TODO|<FILL' DEMO.md; }
c_clean()    { [ "$(git branch --show-current)" = main ] && [ -z "$(git status --porcelain --untracked-files=no)" ]; }
c_release_tag() { git rev-parse -q --verify refs/tags/v1.0.0 >/dev/null && git ls-remote --tags origin v1.0.0 2>/dev/null | grep -q 'refs/tags/v1.0.0'; }

# ---------------------------------------------------------------- the engine --
SCORE=0; SKIPPED=0; FAILS=0; N=0
# item ID POINTS SESSIONS FUNC "what" "how to fix"
item() {
  local id="$1" pts="$2" ses="$3" fn="$4" what="$5" hint="$6" rc
  N=$((N+1)); NOTE=""
  "$fn" >/dev/null 2>&1; rc=$?
  case "$rc" in
    0) printf '[\033[32mPASS\033[0m] %-3s %2d/%-2d  S%-5s %s\n' "$id" "$pts" "$pts" "$ses" "$what"; SCORE=$((SCORE+pts)); PILLAR_SUM=$((PILLAR_SUM+pts))
       [ -n "$NOTE" ] && printf '                         %s\n' "$NOTE" ;;
   77) printf '[\033[33mSKIP\033[0m] %-3s  0/%-2d  S%-5s %s\n' "$id" "$pts" "$ses" "$what"; SKIPPED=$((SKIPPED+pts)); SKIP_IDS="$SKIP_IDS $id"
       [ -n "$NOTE" ] && printf '                         not checked: %s\n' "$NOTE" ;;
    *) printf '[\033[31mFAIL\033[0m] %-3s  0/%-2d  S%-5s %s\n' "$id" "$pts" "$ses" "$what"; FAILS=$((FAILS+1)); FAIL_IDS="$FAIL_IDS $id:$pts"
       [ -n "$NOTE" ] && printf '                         %s\n' "$NOTE"
       printf '                         -> %s\n' "$hint" ;;
  esac
}
SKIP_IDS=""; FAIL_IDS=""; PILLAR_SUM=0
pillar() { # name max
  printf '\n== %s (max %s) ==\n' "$1" "$2"
}
pillar_end() { printf '   subtotal: %s\n' "$PILLAR_SUM"; PILLAR_SUM=0; }

echo "Production readiness of $(basename "$PWD")  (commit $(git rev-parse --short HEAD 2>/dev/null), $(git describe --tags --always 2>/dev/null))"

pillar "A. Reproducibility (sessions 1-5)" 20
item R1 3 1-2   c_pinned     "uv.lock is committed and every dependency is pinned with =="                     "uv add pkg==X.Y.Z ; uv lock ; git add pyproject.toml uv.lock"
item R2 3 3     c_secrets    ".env is not in Git, .env.example is, and the S3 secret is in no file or commit"    "git rm --cached .env ; echo .env >> .gitignore ; git add .env.example"
item R3 2 2     c_lint       "ruff check and ruff format are clean"                                             "uv run ruff check --fix . && uv run ruff format ."
item R4 4 2,5,8 c_tests      "pytest: 20 or more tests pass, none fails"                                        "uv run pytest -q   and read the first failure"
item R5 3 4     c_dvcdata    "data is a DVC pointer (not in Git), the remote is S3, tags data-v1 and data-v2"    "s04/README.md steps 2-5"
item R6 3 5     c_dvcpipe    "dvc.yaml has 3 stages, dvc.lock is committed, dvc status is up to date"           "uv run dvc pull ; uv run dvc repro"
item R7 2 2     c_tags       "at least 5 version tags (v0.x.0), all pushed to origin"                           "git push origin --tags"
pillar_end
pillar "B. Model lifecycle (sessions 6-7)" 12
item M1 4 6     c_mlruns     "MLflow answers and experiment 1 has runs"                                          "docker compose ps in ~/mlops-lab/compose ; uv run dvc repro --force (logs a run)"
item M2 4 7     c_champion   "the registered model churn has the alias @champion"                                "make runs ; make register RUN=<id> ; make promote"
item M3 4 7     c_gate       "the @champion version has tag gate=passed and the data_md5 of its data"           "make promote   (the gate writes the tag)"
pillar_end
pillar "C. Serving and image (sessions 8-9)" 18
item S1 4 8     c_service    "the service answers: /ready, /predict (valid) and /predict (bad input -> 422)"     "curl -i $SERVICE_URL/ready ; make k8s-status ; s12/README.md"
item S2 2 8,13  c_metrics    "/metrics exposes http_requests_total (Prometheus format)"                         "uv add prometheus-fastapi-instrumentator==8.1.0 (session 8)"
item S3 3 9     c_dockerfile "Dockerfile: 2 stages, non-root USER, HEALTHCHECK"                                  "s09/README.md step 2"
item S4 1 9     c_dockerignore ".dockerignore excludes .env and .git"                                            "printf '.env\n.env.*\n.git\n' >> .dockerignore"
item S5 4 9     c_trivy      "Trivy scan of $IMAGE:$TAG passes (no fixable HIGH/CRITICAL)"                      "make image ; make scan   (offline DB: ~/.cache/trivy ; fix by upgrading the library; an ignore file with a dated comment is the last resort)"
item S6 2 9     c_registry   "the local registry ($REGISTRY_URL) holds churn-api tags"                           "make push   (is kind-registry running? docker start kind-registry)"
item S7 2 8     c_apitests   "tests/test_api.py has at least 3 tests"                                           "s08/README.md step 4"
pillar_end
pillar "D. Deployment (sessions 10-12)" 20
item D1 2 10    c_ansible    "Ansible playbook and inventory are committed and pass --syntax-check"             "cd deploy && uv run ansible-playbook --syntax-check deploy.yml"
item D2 4 11,12 c_chart      "Helm chart (dev and prod) renders readinessProbe, livenessProbe and resources"    "helm template x chart/churn-api -f chart/churn-api/values-prod.yaml | less"
item D3 1 12    c_helmlint   "helm lint passes with values-dev and values-prod"                                 "helm lint chart/churn-api -f chart/churn-api/values-dev.yaml"
item D4 2 12    c_prodvals   "values-prod.yaml: at least 2 replicas and a PINNED model (models:/churn/N, not @champion)" "edit chart/churn-api/values-prod.yaml"
item D5 4 11,12 c_release    "Helm release $RELEASE is deployed in namespace $NS and all replicas are ready"     "make helm-deploy ; kubectl --context $KCTX -n $NS get pods"
item D6 4 12    c_routing    "Traefik routes by host: $SERVICE_URL -> 200, other.localhost -> 404"              "make ingress-up ; kubectl --context $KCTX -n $NS get ingress"
item D7 3 10,12 c_rollback   "Makefile has the rollback targets (rollback, helm-rollback)"                     "cp ~/mlops-lab/s13/Makefile . (it has all targets)"
pillar_end
pillar "E. Automation and observability (session 13)" 14
item O1 3 13    c_cifiles    "3 workflows (ci, ml-ci, retrain); ci runs lint, test and scan; no 'uses:'"        "cp -r ~/mlops-lab/s13/.gitea ."
item O2 3 13    c_cirun      "Gitea Actions: the last runs of 'ci' on main include a success"                    "Gitea > Actions ; make runner-up   (needs GITEA_USER and GITEA_PASSWORD for this check)"
item O3 3 13    c_prom       "Prometheus scrapes the API (target up) and the alert rule ChurnApiDown is loaded"  "make mon-up ; make mon-status"
item O4 2 13    c_grafana    "Grafana has the dashboard 'Churn API: RED metrics'"                              "make mon-up ; open $GRAFANA_URL"
item O5 3 13    c_drift      "Evidently is pinned and reports/drift-v1-v2.html exists"                          "make drift"
pillar_end
pillar "F. Documentation and delivery (session 14)" 16
item X1 4 14    c_readme     "README.md has 20+ lines, a Quick start and an Architecture heading, no TODO"      "cp ~/mlops-lab/s14/README.project.md README.md ; edit it"
item X2 5 14    c_runbook    "RUNBOOK.md: Start, Stop, Restart, Logs, Rollback, Health sections with commands, no TODO" "cp ~/mlops-lab/s14/RUNBOOK.md . ; fill every <FILL>"
item X3 3 14    c_demo       "DEMO.md has a timed script (5 or more sections with m:ss times), no TODO"          "cp ~/mlops-lab/s14/DEMO.md . ; edit it"
item X4 2 14    c_clean      "you are on main and no tracked file is modified"                                  "git status ; commit or restore"
item X5 2 14    c_release_tag "tag v1.0.0 exists locally and on origin"                                         "git tag -a v1.0.0 -m 'Capstone: churn mini production' && git push origin v1.0.0"
pillar_end

TOTAL_POSSIBLE=100
echo
echo "=================================================================="
printf ' SCORE: %d / %d\n' "$SCORE" "$TOTAL_POSSIBLE"
[ "$SKIPPED" -gt 0 ] && printf ' not checked: %d points (%s) - they are NOT in the score\n' "$SKIPPED" "${SKIP_IDS# }"
if [ "$FAILS" -gt 0 ]; then
  printf ' failed:'
  for f in $FAIL_IDS; do printf ' %s (%s points)' "${f%%:*}" "${f##*:}"; done; echo
fi
if   [ "$SCORE" -ge 90 ]; then V="PRODUCTION-READY (mini)"
elif [ "$SCORE" -ge 80 ]; then V="DEMO-READY: fix the failed items when you can"
elif [ "$SCORE" -ge 60 ]; then V="ALMOST: fix the failed items before the demo"
else V="NOT YET: start from the highest-point failed items"; fi
printf ' verdict: %s\n' "$V"
echo "=================================================================="
echo "SCORE=$SCORE/$TOTAL_POSSIBLE"
[ "$SCORE" -ge 80 ]

# shellcheck shell=bash
# =============================================================================
# preflight-lib.sh — shared helpers for the per-session checks sNN/preflight.sh.
# Not run directly: every sNN/preflight.sh sets SESSION and sources this file.
#
# A session pre-flight has two parts:
#   1. the laptop    — scripts/preflight.sh sNN (tools, images, ports, hardware)
#   2. the project   — ~/work/churn-mlops is at the END state of the previous session
#                      (env PROJECT=/other/path checks another folder)
# Read-only: it only reads files, Git, and the HTTP answers of the lab services.
# Works with bash 3.2 (macOS) and bash 5 (Ubuntu / WSL).
# =============================================================================
set -uo pipefail
export GIT_TERMINAL_PROMPT=0   # never hang on a password prompt

LAB=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PROJECT="${PROJECT:-$HOME/work/churn-mlops}"
S3_URL="${S3_ENDPOINT_URL:-}"
MLFLOW_URI="${MLFLOW_TRACKING_URI:-http://localhost:5050}"; MLFLOW_URI="${MLFLOW_URI%/}"
GITEA_URL="${GITEA_URL:-http://localhost:3000}"; GITEA_URL="${GITEA_URL%/}"
P_FAILS=0; P_WARNS=0; P_PASSES=0; MACHINE=0; IN_PROJECT=no

pass() { printf '  \033[32mPASS\033[0m  %s\n' "$*"; P_PASSES=$((P_PASSES+1)); }
warn() { printf '  \033[33mWARN\033[0m  %s\n' "$1"; [ -n "${2:-}" ] && printf '        -> %s\n' "$2"; P_WARNS=$((P_WARNS+1)); }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; [ -n "${2:-}" ] && printf '        -> %s\n' "$2"; P_FAILS=$((P_FAILS+1)); }
info() { printf '  \033[36mINFO\033[0m  %s\n' "$*"; }
# check FUNC "what is checked" "how to fix"   (FAIL if FUNC returns non-zero)
check() { if "$1"; then pass "$2"; else fail "$2" "${3:-}"; fi; }
# soft  FUNC "what is checked" "how to fix"   (only WARN)
soft()  { if "$1"; then pass "$2"; else warn "$2" "${3:-}"; fi; }

# --- small building blocks (call them inside the project folder) -------------
envval()     { sed -n "s/^$1=//p" .env 2>/dev/null | tail -1 | tr -d '\r'; }
tracked()    { for f in "$@"; do git ls-files --error-unmatch "$f" >/dev/null 2>&1 || return 1; done; }
has_tag()    { git rev-parse -q --verify "refs/tags/$1" >/dev/null; }
tag_pushed() { git ls-remote --tags origin "$1" 2>/dev/null | grep -q "refs/tags/$1"; }
pinned()     { for p in "$@"; do grep -q "\"$p==" pyproject.toml 2>/dev/null || return 1; done; }
on_main()    { [ "$(git branch --show-current 2>/dev/null)" = main ]; }
origin_gitea() { git remote get-url origin 2>/dev/null | grep -q "localhost:3000"; }
http_code()  { curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$1" 2>/dev/null; }
s3_url()     { local u="$S3_URL"; [ -n "$u" ] || u=$(envval S3_ENDPOINT_URL); u="${u:-http://localhost:8333}"; echo "${u%/}"; }
s3_up()      { local c; c=$(http_code "$(s3_url)"); [ -n "$c" ] && [ "$c" != "000" ]; }
gitea_up()   { [ "$(http_code "$GITEA_URL/api/healthz")" = "200" ]; }
mlflow_up()  { curl -fsS --max-time 5 "$MLFLOW_URI/health" 2>/dev/null | grep -q OK; }
mlf_get()    { curl -fsS --max-time 10 "$MLFLOW_URI/$1" 2>/dev/null; }
jq_py()      { python3 -c "import json,sys; d=json.load(sys.stdin)
$1" 2>/dev/null; }

# Tag of the previous session: FAIL if missing locally, WARN if Gitea does not have it.
check_tag() { # tag "session N"
  if has_tag "$1"; then
    pass "tag $1 exists ($2)"
    if tag_pushed "$1"; then pass "tag $1 is on Gitea"
    else warn "tag $1 is not on Gitea (or Gitea is not running)" "git push origin $1   (start Gitea first: cd ~/mlops-lab/compose && docker compose up -d gitea)"; fi
  else
    fail "tag $1 is missing — $2 is not finished" "finish $2 (its README, last step) and run: ~/mlops-lab/scripts/verify.sh $3"
  fi
}

# --- part 1: header, the laptop, the course repo -----------------------------
preflight_begin() {
  local n=$((10#$SESSION))
  echo "=================================================================="
  echo " Session $n pre-flight — run it BEFORE the class starts"
  echo "=================================================================="
  echo
  echo "### Part 1: the laptop (scripts/preflight.sh s$SESSION)"
  "$LAB/scripts/preflight.sh" "s$SESSION"; MACHINE=$?
  echo
  echo "### Part 2: the course repo and your project"
  echo "[Course repo] $LAB"
  if git -C "$LAB" rev-parse --git-dir >/dev/null 2>&1; then
    if [ -z "$(git -C "$LAB" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
      pass "no local edits inside the course repo (git pull will work)"
    else
      warn "files inside the course repo were edited — git pull may refuse" "see them: git -C $LAB status   (students: copy files out, never edit inside ~/mlops-lab)"
    fi
    info "last update: $(git -C "$LAB" log -1 --format='%cd' --date=short 2>/dev/null) — run  git -C $LAB pull  before class"
  else
    warn "the course repo is not a Git clone" "git clone https://github.com/srsalari/MLOps-Fundamental.git ~/mlops-lab"
  fi
}

# Enter the project. Returns 1 (and counts a FAIL) when it is not the course project.
project_begin() { # "end of session N-1"
  echo "[Project start state: $1] $PROJECT"
  if ! cd "$PROJECT" 2>/dev/null; then
    fail "project folder not found" "the project lives in ~/work/churn-mlops; if yours is elsewhere: PROJECT=/path/to/it $0"
    return 1
  fi
  if [ ! -f pyproject.toml ] || ! git rev-parse --git-dir >/dev/null 2>&1; then
    fail "this folder is not the course project (no pyproject.toml or not a Git repo)" "PROJECT=/path/to/churn-mlops $0"
    return 1
  fi
  IN_PROJECT=yes
  pass "project found (branch $(git branch --show-current 2>/dev/null), commit $(git rev-parse --short HEAD 2>/dev/null))"
  if [ -z "$(git status --porcelain --untracked-files=no 2>/dev/null)" ]; then
    pass "no uncommitted changes in tracked files"
  else
    warn "there are uncommitted changes" "git status   — commit or restore them before the new session"
  fi
  return 0
}

# Shared service checks used by several sessions.
svc_s3()     { check s3_up     "SeaweedFS S3 answers at $(s3_url)" "cd ~/mlops-lab/compose && docker compose up -d seaweedfs   (wait until docker compose ps shows healthy)"; }
svc_gitea()  { soft  gitea_up  "Gitea answers at $GITEA_URL"       "cd ~/mlops-lab/compose && docker compose up -d gitea"; }
svc_mlflow() { check mlflow_up "MLflow server answers at $MLFLOW_URI" "cd ~/mlops-lab/compose && docker compose up -d seaweedfs mlflow ; curl $MLFLOW_URI/health"; }

# --- the verdict --------------------------------------------------------------
preflight_end() {
  local n=$((10#$SESSION)) m="READY"
  [ "$MACHINE" -eq 0 ] || m="NOT READY"
  echo
  echo "=================================================================="
  printf ' part 1 (laptop): %s   part 2: %d passed, %d warnings, %d failures\n' "$m" "$P_PASSES" "$P_WARNS" "$P_FAILS"
  if [ "$MACHINE" -eq 0 ] && [ "$P_FAILS" -eq 0 ]; then
    printf ' \033[32mREADY\033[0m to start session %d\n' "$n"
    echo "=================================================================="
    exit 0
  fi
  printf ' \033[31mNOT READY\033[0m for session %d — fix every FAIL line (the fix is on the -> line) or ask the trainer\n' "$n"
  echo "=================================================================="
  exit 1
}

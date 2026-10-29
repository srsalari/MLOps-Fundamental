#!/usr/bin/env bash
# =============================================================================
# preflight.sh — checks a student laptop is ready for the MLOps Fundamentals labs.
#
#   preflight.sh [sNN]      sNN = s3, s03 or 3
#
#   preflight.sh s03   checks only what session 3 AND all earlier sessions need
#   preflight.sh       checks the whole course (all 14 sessions)
#
# Things that belong to later sessions are NOT failures: they are listed as INFO
# in a short [Later sessions] section. READY / NOT READY depends only on the
# items needed up to the chosen session.
#
# Exit code: 0 = ready (warnings allowed), 1 = at least one FAIL, 2 = bad usage.
# Read-only: it never starts, stops or pulls anything.
# Works with bash 3.2 (macOS) and bash 5 (Ubuntu / WSL).
# =============================================================================
set -uo pipefail

# -----------------------------------------------------------------------------
# REQUIREMENTS TABLE  (the trainer edits THIS part)
#
# One line per requirement:   SESSION|KIND|WHAT|DESCRIPTION
#   SESSION      first session that needs it (it stays needed for later ones)
#   KIND         tool    command-line tool that must exist (FAIL if missing)
#                tool?   optional tool (WARN if missing)
#                python  Python version managed by uv (WHAT = version)
#                docker  Docker check: engine | compose | buildx
#                image   Docker image already loaded; WHAT = variable name in
#                        versions.env (e.g. GITEA_IMAGE)
#                port    free TCP port on 127.0.0.1; WHAT = VERSIONS_VAR:DEFAULT
#                        (VERSIONS_VAR may be empty, e.g. ":8081")
#   DESCRIPTION  free text shown only for ports
# Hardware (CPU/RAM/disk) is checked for every session, it is not in the table.
# -----------------------------------------------------------------------------
REQUIREMENTS='
1|tool|git|
1|tool|make|
1|tool|uv|
1|python|3.12|
2|docker|engine|
2|docker|compose|
2|image|GITEA_IMAGE|
2|port|PORT_GITEA_HTTP:3000|Gitea web
2|port|PORT_GITEA_SSH:2222|Gitea ssh
3|image|SEAWEEDFS_IMAGE|
3|image|NGINX_IMAGE|
3|image|PYTHON_BASE_IMAGE|
3|port|PORT_S3:8333|SeaweedFS S3
3|port|PORT_SEAWEED_MASTER:9333|SeaweedFS master
3|port|PORT_SEAWEED_FILER:8888|SeaweedFS filer
3|port|:8081|session 3 demo web server
3|port|:8082|session 3 demo web server
6|image|MLFLOW_SERVER_IMAGE|
6|port|PORT_MLFLOW:5050|MLflow server
8|port|:8000|session 8 prediction API
9|docker|buildx|
9|tool|trivy|
9|tool?|syft|
9|image|REGISTRY_IMAGE|
9|image|UV_IMAGE|
9|port|:8001|session 9 API container
9|port|PORT_REGISTRY:5001|local image registry
10|image|PRACTICE_VM_IMAGE|
10|port|:2223|practice VM ssh
10|port|:8090|practice VM web (Nginx)
11|tool|kind|
11|tool|kubectl|
11|image|KIND_NODE_IMAGE|
11|port|PORT_INGRESS_HTTP:8080|ingress HTTP
11|port|PORT_INGRESS_HTTPS:8443|ingress HTTPS
12|tool|helm|
13|image|ACT_RUNNER_IMAGE|
13|image|CI_JOB_IMAGE|
13|image|PROMETHEUS_IMAGE|
13|image|GRAFANA_IMAGE|
13|port|PORT_PROMETHEUS:9090|Prometheus
13|port|PORT_GRAFANA:3001|Grafana
13|port|PORT_API_MON:8003|session 13 API container (monitoring)
14|port|:8011|session 14 API container (clean clone)
'
# Sessions 4, 5 and 7 need nothing new (DVC and the Python libraries come from
# the project itself through uv). Sessions 8+ reuse the tools above.
LAST_SESSION=14

# --- output helpers ----------------------------------------------------------
FAILS=0; WARNS=0
pass() { printf '  \033[32mPASS\033[0m  %s\n' "$*"; }
warn() { printf '  \033[33mWARN\033[0m  %s\n' "$*"; WARNS=$((WARNS+1)); }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; FAILS=$((FAILS+1)); }
info() { printf '  \033[36mINFO\033[0m  %s\n' "$*"; }
need() { command -v "$1" >/dev/null 2>&1; }

usage() {
  echo "usage: $(basename "$0") [sNN]      (sNN = s3, s03 or 3; sessions 1-$LAST_SESSION)"
  echo "  $(basename "$0") s03   check only what session 3 and the earlier sessions need"
  echo "  $(basename "$0")       check the whole course"
}

# --- argument ----------------------------------------------------------------
TARGET=99; FULL=yes
if [ $# -gt 1 ]; then usage >&2; exit 2; fi
if [ $# -eq 1 ]; then
  case "$1" in -h|--help) usage; exit 0;; esac
  A=$(printf '%s' "$1" | tr 'A-Z' 'a-z')
  A=${A#s}
  case "$A" in
    ''|*[!0-9]*) echo "error: bad session '$1'" >&2; usage >&2; exit 2;;
  esac
  A=$((10#$A))
  if [ "$A" -lt 1 ] || [ "$A" -gt "$LAST_SESSION" ]; then
    echo "error: session must be between 1 and $LAST_SESSION (got '$1')" >&2; usage >&2; exit 2
  fi
  TARGET=$A; FULL=no
fi

# --- environment -------------------------------------------------------------
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
OS=$(uname -s); ARCH=$(uname -m)
WSL=$(grep -qi microsoft /proc/version 2>/dev/null && echo yes || echo no)
if [ "$FULL" = yes ]; then LABEL="the full course"; else LABEL="session $TARGET"; fi
echo "MLOps Fundamentals — lab pre-flight for $LABEL ($OS/$ARCH, WSL=$WSL)"
[ "$FULL" = yes ] && echo "tip: run $(basename "$0") s03 to check only what today's session needs"

VERSIONS="$SCRIPT_DIR/../versions.env"
HAVE_VERSIONS=no
if [ -f "$VERSIONS" ]; then
  # shellcheck source=/dev/null
  . "$VERSIONS"; HAVE_VERSIONS=yes
fi
# MLflow image: from versions.env, else the default written in the compose file.
if [ -z "${MLFLOW_SERVER_IMAGE:-}" ] && [ -f "$SCRIPT_DIR/../compose/docker-compose.yml" ]; then
  MLFLOW_SERVER_IMAGE=$(sed -n 's/^[[:space:]]*image:[[:space:]]*\${MLFLOW_SERVER_IMAGE:-\([^}]*\)}.*/\1/p' "$SCRIPT_DIR/../compose/docker-compose.yml" | head -1)
fi

# Docker state is read once (read-only).
DOCKER_OK=no; DOCKER_PS=""
if need docker && docker info >/dev/null 2>&1; then
  DOCKER_OK=yes
  DOCKER_PS=$(docker ps --format '{{.Names}}|{{.Label "com.docker.compose.project"}}|{{.Ports}}' 2>/dev/null || true)
fi

# Items of later sessions: LATER_n holds a comma-separated list for session n.
n=1; while [ "$n" -le "$LAST_SESSION" ]; do eval "LATER_$n="; n=$((n+1)); done
add_later() { # session, text
  eval "cur=\$LATER_$1"
  if [ -z "$cur" ]; then eval "LATER_$1=\"\$2\""; else eval "LATER_$1=\"\$cur, \$2\""; fi
}

# --- individual checks -------------------------------------------------------
tool_version() {
  case "$1" in
    kubectl)   kubectl version --client 2>/dev/null | head -1;;
    helm)      helm version --short 2>/dev/null | head -1;;
    *)         "$1" --version 2>/dev/null | head -1;;
  esac
}
install_hint() { # tool -> fix hint
  case "$1" in
    make) [ "$OS" = Darwin ] && echo "run: brew install make (or xcode-select --install)" || echo "run: sudo apt install make";;
    git)  [ "$OS" = Darwin ] && echo "run: brew install git" || echo "run: sudo apt install git";;
    multipass) echo "install Multipass (see the BOM; Windows/WSL needs a special setup) or ask the trainer";;
    *)    echo "run scripts/install-from-bundle.sh";;
  esac
}
check_tool() { # name optional(yes|no)
  if need "$1"; then pass "$1: $(tool_version "$1")"
  elif [ "$2" = yes ]; then warn "$1 not found (optional) — run scripts/install-from-bundle.sh"
  else fail "$1 not found — $(install_hint "$1")"; fi
}
check_python() {
  if ! need uv; then fail "Python $1 cannot be checked because uv is missing — run scripts/install-from-bundle.sh"
  elif uv python find "$1" >/dev/null 2>&1; then pass "Python $1 (uv-managed)"
  else fail "Python $1 not installed — run: uv python install $1"; fi
}
check_docker() {
  case "$1" in
    engine)
      if [ "$DOCKER_OK" = yes ]; then
        pass "Docker engine reachable ($(docker version -f '{{.Server.Version}}' 2>/dev/null))"
        local dmem; dmem=$(( $(docker info -f '{{.MemTotal}}' 2>/dev/null || echo 0) / 1073741824 ))
        if [ "$dmem" -ge 7 ]; then pass "Memory available to Docker: ${dmem}GB"
        else warn "Docker only has ${dmem}GB — raise it to 8GB or more (Colima: colima start --memory 8; Docker Desktop: Settings > Resources)"; fi
      elif need docker; then
        fail "Docker is installed but not running — macOS: colima start (or open Docker Desktop); Linux/WSL: sudo systemctl start docker"
      else
        fail "Docker is not installed — Linux/WSL: sudo apt install docker.io docker-compose-v2 docker-buildx; macOS: brew install colima docker docker-compose"
      fi;;
    compose)
      [ "$DOCKER_OK" = yes ] || return 0
      docker compose version >/dev/null 2>&1 && pass "docker compose v2" \
        || fail "docker compose v2 plugin missing — Linux/WSL: sudo apt install docker-compose-v2; macOS: brew install docker-compose";;
    buildx)
      [ "$DOCKER_OK" = yes ] || return 0
      docker buildx version >/dev/null 2>&1 && pass "docker buildx" \
        || fail "docker buildx missing — Linux/WSL: sudo apt install docker-buildx; macOS: brew install docker-buildx";;
  esac
}
check_image() { # variable name from versions.env
  local img="${!1:-}"
  if [ -z "$img" ]; then warn "image $1 is not defined in versions.env — ask the trainer"; return 0; fi
  local full=$img
  img=${img%@*}   # show the name without the pinned digest
  [ "$DOCKER_OK" = yes ] || return 0
  # An image pulled by digest (kind does this) has no tag locally: try both forms.
  if docker image inspect "$img" >/dev/null 2>&1 || docker image inspect "$full" >/dev/null 2>&1; then pass "$img"
  else fail "image missing: $img — run scripts/install-session-pack.sh (or: docker load -i <pack>.tar)"; fi
}
check_port() { # port, description
  local p=$1 d=$2 line owner proj prog
  if ! (exec 3<>/dev/tcp/127.0.0.1/"$p") 2>/dev/null; then pass "port $p free ($d)"; return 0; fi
  line=$(printf '%s\n' "$DOCKER_PS" | grep -F ":$p->" | head -1)
  if [ -n "$line" ]; then
    owner=${line%%|*}; proj=${line#*|}; proj=${proj%%|*}
    if [ "$proj" = mlops-lab ]; then pass "port $p used by lab container $owner ($d)"
    else warn "port $p is used by container $owner (not the lab) — stop it or change the lab port"; fi
  else
    prog=""
    need lsof && prog=$(lsof -nP -iTCP:"$p" -sTCP:LISTEN 2>/dev/null | awk 'NR==2{print $1}')
    if [ -n "$prog" ]; then warn "port $p is used by program $prog (not the lab) — stop it or change the lab port"
    else warn "port $p is busy (another program, or Docker is not running) — stop it or change the lab port"; fi
  fi
}

# Walk the table for one section (list of KINDs); run what is needed, remember the rest.
run_section() { # title, kinds (space-separated)
  local title=$1 kinds=$2 s kind what desc shown=no var def val name
  while IFS='|' read -r s kind what desc; do
    [ -z "$s" ] && continue
    case " $kinds " in *" $kind "*) ;; *) continue;; esac
    if [ "$s" -gt "$TARGET" ]; then
      case "$kind" in
        port)  var=${what%%:*}; def=${what##*:}; val=$def
               [ -n "$var" ] && [ -n "${!var:-}" ] && val=${!var}
               name="port $val";;
        image) name="${!what:-$what}"; name=${name%@*};;
        docker) name="docker $what";;
        python) name="Python $what";;
        *) name=$what;;
      esac
      add_later "$s" "$name"; continue
    fi
    if [ "$shown" = no ]; then echo "[$title]"; shown=yes; fi
    case "$kind" in
      tool)   check_tool "$what" no;;
      'tool?') check_tool "$what" yes;;
      python) check_python "$what";;
      docker) check_docker "$what";;
      image)  check_image "$what";;
      port)   var=${what%%:*}; def=${what##*:}; val=$def
              [ -n "$var" ] && [ -n "${!var:-}" ] && val=${!var}
              check_port "$val" "$desc";;
    esac
  done <<EOF
$REQUIREMENTS
EOF
}

# --- hardware (always) -------------------------------------------------------
echo "[Hardware]"
if [ "$OS" = Darwin ]; then
  SYSCTL=$(command -v sysctl || echo /usr/sbin/sysctl)   # /usr/sbin may be missing from PATH
  CPUS=$("$SYSCTL" -n hw.ncpu 2>/dev/null || echo 0); MEM_GB=$(( $("$SYSCTL" -n hw.memsize 2>/dev/null || echo 0) / 1073741824 ))
else
  CPUS=$(nproc 2>/dev/null || echo 0); MEM_GB=$(( $(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null || echo 0) / 1048576 ))
fi
if [ "$CPUS" -ge 4 ]; then pass "CPU cores: $CPUS"; else fail "CPU cores: $CPUS (need 4 or more) — use a stronger laptop or ask the trainer"; fi
if   [ "$MEM_GB" -ge 15 ]; then pass "RAM: ${MEM_GB}GB"
elif [ "$MEM_GB" -ge 7 ];  then warn "RAM: ${MEM_GB}GB — works, but close other programs and stop unused services between labs"
else fail "RAM: ${MEM_GB}GB (need 8GB or more, 16GB recommended) — ask the trainer about a shared server"; fi
DISK_GB=$(df -Pk "$HOME" | awk 'NR==2{print int($4/1048576)}')
if   [ "$DISK_GB" -ge 40 ]; then pass "Free disk in \$HOME: ${DISK_GB}GB"
elif [ "$DISK_GB" -ge 25 ]; then warn "Free disk: ${DISK_GB}GB (40GB recommended) — free some space before the Docker sessions"
else fail "Free disk: ${DISK_GB}GB (need 25GB or more) — free some space"; fi
if [ "$WSL" = yes ]; then
  case "$PWD/" in /mnt/*) warn "current directory is under /mnt/ (Windows disk, very slow) — work inside the WSL filesystem, e.g. ~/work";; esac
  case "$(cd "$HOME/work" 2>/dev/null && pwd -P)/" in
    /mnt/*) warn "~/work is under /mnt/ (Windows disk, very slow) — move your projects to the WSL filesystem (e.g. /home/<you>/work)";;
  esac
fi

# --- the table-driven sections ----------------------------------------------
run_section "Lab CLI tools"      "tool tool? python"
run_section "Container runtime"  "docker"
run_section "Lab images loaded"  "image"
run_section "Ports on 127.0.0.1" "port"

if [ "$HAVE_VERSIONS" = no ]; then
  warn "versions.env not found next to scripts/ — image names and ports use defaults"
fi

# --- later sessions ----------------------------------------------------------
LATER_TEXT=""
n=1; while [ "$n" -le "$LAST_SESSION" ]; do
  eval "cur=\$LATER_$n"
  [ -n "$cur" ] && LATER_TEXT="$LATER_TEXT  \033[36mINFO\033[0m  from session $n: $cur\n"
  n=$((n+1))
done
if [ -n "$LATER_TEXT" ]; then
  echo "[Later sessions] (not needed yet, not counted)"
  printf '%b' "$LATER_TEXT"
fi

echo
if [ "$FAILS" -eq 0 ]; then
  printf '\033[32mREADY\033[0m for %s (%d warnings)\n' "$LABEL" "$WARNS"; exit 0
else
  printf '\033[31mNOT READY\033[0m for %s: %d failures, %d warnings — fix the FAIL items or ask the trainer\n' "$LABEL" "$FAILS" "$WARNS"; exit 1
fi

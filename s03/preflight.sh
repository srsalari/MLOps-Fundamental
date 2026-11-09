#!/usr/bin/env bash
# =============================================================================
# s03/preflight.sh — ready for session 3? Run it BEFORE class:
#     ~/mlops-lab/s03/preflight.sh                 (PROJECT=/path to check another folder)
# Checks the laptop (Docker memory, SeaweedFS/nginx/python images, ports) and
# that ~/work/churn-mlops is at the end state of session 2 (Gitea, tests, v0.1.0).
# Exit code: 0 = ready, 1 = something to fix. Read-only.
# =============================================================================
SESSION=03
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../scripts/preflight-lib.sh"
preflight_begin

s02_tools()  { for t in ruff pytest pre-commit; do grep -qE "\"$t(==|>=|~=)" pyproject.toml || return 1; done; tracked pyproject.toml uv.lock; }
s02_tests()  { [ "$(cat tests/test_*.py 2>/dev/null | grep -c '^def test_')" -ge 4 ]; }
s02_hooks()  { H=$(git rev-parse --git-path hooks); tracked .pre-commit-config.yaml \
                 && grep -q pre-commit "$H/pre-commit" 2>/dev/null && grep -q pre-commit "$H/pre-push" 2>/dev/null; }
compose_env(){ [ -f "$LAB/compose/.env" ]; }

if project_begin "end of session 2"; then
  check origin_gitea "remote origin points to Gitea (localhost:3000)" "git remote add origin http://localhost:3000/student/churn-mlops.git   (s02/README.md)"
  check s02_tools    "ruff, pytest and pre-commit are dev dependencies; pyproject.toml and uv.lock committed" "uv add --dev ruff pytest pre-commit   (s02/README.md, step 4), then commit pyproject.toml and uv.lock"
  check s02_tests    "at least 4 tests in tests/"                      "write the 4th test (s02/README.md, step 3)"
  check s02_hooks    "pre-commit hooks installed (pre-commit + pre-push)" "uv run pre-commit install --hook-type pre-commit --hook-type pre-push"
  check_tag v0.1.0 "session 2" s02
fi
echo "[Lab services]"
check compose_env "~/mlops-lab/compose/.env exists" "cp ~/mlops-lab/compose/.env.example ~/mlops-lab/compose/.env"
svc_gitea
preflight_end

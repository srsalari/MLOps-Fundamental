#!/usr/bin/env bash
# =============================================================================
# s01/preflight.sh — is this laptop ready for session 1? Run it BEFORE class:
#     ~/mlops-lab/s01/preflight.sh
# Session 1 needs only git, make, uv and Python 3.12, plus internet for the
# first "uv sync". There is no project yet: it is created in step 2.
# Exit code: 0 = ready, 1 = something to fix. Read-only.
# =============================================================================
SESSION=01
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../scripts/preflight-lib.sh"
preflight_begin

no_project() { [ ! -f "$PROJECT/pyproject.toml" ]; }
internet()   { c=$(http_code https://pypi.org/simple/); [ -n "$c" ] && [ "$c" != "000" ]; }

echo "[Before step 1]"
soft no_project "$PROJECT does not exist yet (it is created in step 2)" \
  "it already has a pyproject.toml: uv init will stop. Rename the old folder (mv $PROJECT $PROJECT.old) or ask the trainer"
soft internet "internet reaches pypi.org (needed for the first uv sync)" \
  "no internet in class? the trainer gives you the offline pack: scripts/install-from-bundle.sh"
preflight_end

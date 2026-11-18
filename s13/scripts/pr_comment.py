"""Post (or update) one comment on a pull request in Gitea.

Used by the ML CI workflow: the body is the markdown table from `dvc metrics diff --md`.
The comment starts with a hidden marker, so a second run EDITS the same comment instead
of adding a new one for every push.

Usage (inside a Gitea Actions job):
    python scripts/pr_comment.py metrics-diff.md

Environment (all set by the workflow):
    GITEA_INTERNAL   address of Gitea inside the Docker network, e.g. http://gitea:3000
    GITEA_TOKEN      the job token (secrets.GITHUB_TOKEN)
    REPO             owner/name, e.g. student/churn-mlops
    PR_NUMBER        pull request number
"""

import json
import os
import sys
import urllib.request

MARKER = "<!-- metrics-diff -->"


def build_body(table: str, title: str = "Metrics change") -> str:
    """The comment text: hidden marker, a title, then the table from DVC."""
    table = table.strip() or "_DVC found no metrics to compare._"
    return f"{MARKER}\n### {title}\n\n{table}\n"


def find_comment(comments: list[dict]) -> dict | None:
    """The first comment that carries our marker (None if there is no such comment)."""
    return next((c for c in comments if MARKER in c.get("body", "")), None)


def call(method: str, url: str, token: str, payload: dict | None = None):
    """One HTTP request to the Gitea API; returns the decoded JSON answer."""
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"token {token}")
    req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=20) as resp:
        return json.loads(resp.read() or b"null")


def main() -> int:
    env = os.environ
    base = f"{env['GITEA_INTERNAL']}/api/v1/repos/{env['REPO']}"
    token, number = env["GITEA_TOKEN"], env["PR_NUMBER"]
    body = build_body(open(sys.argv[1]).read())
    existing = find_comment(call("GET", f"{base}/issues/{number}/comments", token))
    if existing:
        call("PATCH", f"{base}/issues/comments/{existing['id']}", token, {"body": body})
        print(f"updated comment {existing['id']} on PR #{number}")
    else:
        new = call("POST", f"{base}/issues/{number}/comments", token, {"body": body})
        print(f"created comment {new['id']} on PR #{number}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

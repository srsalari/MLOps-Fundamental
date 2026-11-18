"""Data drift report with Evidently: data version 1 (reference) against version 2 (current).

Usage (needs the `drift` dependency group and the DVC remote):
    uv run --group drift python scripts/drift_report.py
    uv run --group drift python scripts/drift_report.py --reference data-v1 --current data-v2

What it does:
  1. `dvc get` downloads data/raw/churn.csv of the two Git tags into a temp folder.
  2. Evidently compares every column of the current data with the reference data.
  3. It writes an HTML report (open it in a browser) and prints a short table.

Added in Session 13. Evidently is imported inside main(), so the pure function `summarize`
can be tested without installing it.
"""

import argparse
import pathlib
import subprocess
import sys
import tempfile
import warnings


def fetch(rev: str, folder: pathlib.Path) -> pathlib.Path:
    """Download data/raw/churn.csv as it was at Git tag/commit `rev` (uses the DVC remote)."""
    out = folder / f"churn-{rev}.csv"
    cmd = ["dvc", "get", ".", "data/raw/churn.csv", "--rev", rev, "-o", str(out)]
    subprocess.run(cmd, check=True, capture_output=True)
    return out


def summarize(snapshot: dict) -> list[dict]:
    """Turn `snapshot.dict()` of Evidently into rows: column, method, score, threshold, drift.

    Distance methods (Wasserstein, Jensen-Shannon) say "drift" when the score is at or above
    the threshold. Statistical tests that return a p-value say "drift" when it is BELOW it.
    """
    rows = []
    for m in snapshot["metrics"]:
        cfg = m["config"]
        if not cfg["type"].endswith("ValueDrift"):
            continue
        method, threshold, score = cfg["method"], cfg["threshold"], m["value"]
        p_value = "p_value" in method.lower() or "p-value" in method.lower()
        drift = score < threshold if p_value else score >= threshold
        rows.append(
            {
                "column": cfg["column"],
                "method": method,
                "score": round(score, 4),
                "threshold": threshold,
                "drift": drift,
            }
        )
    return rows


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--reference", default="data-v1", help="Git tag of the old data")
    ap.add_argument("--current", default="data-v2", help="Git tag of the new data")
    ap.add_argument("--out", default="reports/drift-v1-v2.html")
    a = ap.parse_args()

    # Evidently has regex strings that Python 3.12 warns about the first time it compiles them.
    warnings.simplefilter("ignore", SyntaxWarning)
    import pandas as pd
    from evidently import Report
    from evidently.presets import DataDriftPreset

    with tempfile.TemporaryDirectory() as tmp:
        ref = pd.read_csv(fetch(a.reference, pathlib.Path(tmp)))
        cur = pd.read_csv(fetch(a.current, pathlib.Path(tmp)))
    snapshot = Report([DataDriftPreset()]).run(cur, ref)

    out = pathlib.Path(a.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    snapshot.save_html(str(out))

    rows = summarize(snapshot.dict())
    print(f"reference {a.reference}: {len(ref)} rows   current {a.current}: {len(cur)} rows")
    print(f"{'column':18} {'method':32} {'score':>7}  drift")
    for r in rows:
        print(
            f"{r['column']:18} {r['method']:32} {r['score']:7.4f}  {'YES' if r['drift'] else 'no'}"
        )
    n = sum(r["drift"] for r in rows)
    print(f"{n} of {len(rows)} columns drifted")
    print(f"report: {out}  (open it in a browser)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

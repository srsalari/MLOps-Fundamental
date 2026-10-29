"""Stage 3: score the test split and write metrics.json.

Session 5 (DVC Pipeline) file: the third and last stage of the pipeline, `evaluate`. It
tests the saved model on the test data (`test.csv`), which the model has never seen, and
writes two numbers, roc_auc and f1, to `metrics.json`.

How to run:

    make train                          # the whole pipeline (preprocess, train, evaluate)
    uv run python -m churn.evaluate     # only this stage

Inputs: `models/model.joblib`, `data/processed/test.csv` and the `eval.threshold` key of
`params.yaml`.
Output: `metrics.json` (defined with `cache: false` in `dvc.yaml`, so it stays in git and
can be compared with `dvc metrics show` / `dvc metrics diff`).

Session 6 note: this file is replaced by a new version (`s06/churn/evaluate.py`) that also
logs the result to MLflow. The `score` function there is exactly the same as here.
The explanation in Persian is in CODE.md.
"""

import argparse
import json
import pathlib

import joblib
import pandas as pd
import yaml
from sklearn.metrics import f1_score, roc_auc_score

from churn.preprocess import OUT_DIR, TARGET


def score(model, df: pd.DataFrame, threshold: float) -> dict:
    """Compute roc_auc and f1 of `model` on the table `df`.

    We return two metrics because each tells something different. roc_auc works with the
    probabilities themselves (no threshold) and shows how well the model separates customers
    who left from those who stayed. f1 needs a hard 0/1 prediction, so the probability is
    turned into one with a threshold.

    Args:
        model: trained model with a `predict_proba` method (the Pipeline).
        df: test table that includes the target column.
        threshold: decision threshold; if the churn probability is higher, we predict "leaves".

    Returns:
        A dict `{"roc_auc": ..., "f1": ...}` rounded to four decimals.
    """
    X, y = df.drop(columns=[TARGET]), df[TARGET]
    # [:, 1] means only the second column (probability of class 1 = the customer leaves).
    proba = model.predict_proba(X)[:, 1]
    return {
        "roc_auc": round(roc_auc_score(y, proba), 4),
        # proba > threshold is an array of True/False (the hard prediction); f1 works with it.
        "f1": round(f1_score(y, proba > threshold), 4),
    }


def main(config: str) -> dict:
    """Load model + test split, compute metrics, write `metrics.json`, return the metrics.

    Args:
        config: path of the YAML settings file (default `params.yaml`).

    Returns:
        The same metrics dict.
    """
    p = yaml.safe_load(open(config))
    model = joblib.load("models/model.joblib")
    metrics = score(model, pd.read_csv(OUT_DIR / "test.csv"), p["eval"]["threshold"])
    # indent=2: the JSON file is readable and its git diff is easy to understand.
    pathlib.Path("metrics.json").write_text(json.dumps(metrics, indent=2))
    print(metrics)
    return metrics


# Runs only when executed directly (`python -m churn.evaluate`).
if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default="params.yaml")
    main(ap.parse_args().config)

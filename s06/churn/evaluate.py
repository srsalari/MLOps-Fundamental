"""Stage 3: score the test split, write metrics.json and log the run to MLflow.

Session 6 (MLflow Tracking) file; it replaces the Session 5 `evaluate.py`. The old work
(computing roc_auc and f1 and writing `metrics.json`) is the same, but now every run is also
recorded in MLflow: parameters, metrics, files and the model itself. We call this record a
run, and all runs of the project are collected in one experiment named `churn`, so they can
be compared later in the MLflow web UI.

How to run:

    make train                          # whole pipeline with dvc repro (evaluate is the last stage)
    uv run dvc exp run -S train.C=0.1   # an experiment with another C; each one makes a run
    uv run dvc exp run -f -S train.C=0.1  # repeat an experiment already run (without -f: cache)
    uv run python -m churn.evaluate     # only this stage

Inputs: `models/model.joblib`, `data/processed/test.csv`, `params.yaml` and (optional)
`data/raw/churn.csv.dvc` to read the md5 of the data.
Outputs: `metrics.json` and one run on the MLflow server (address from the environment
variable `MLFLOW_TRACKING_URI`; default `http://localhost:5050`). The MLflow server stores the
run files in the bucket named `mlflow` in SeaweedFS (S3); the client does not talk to S3
directly.

The MLflow server must be running (`docker compose up -d seaweedfs mlflow`). If it is off,
we stop on purpose with a clear message; the reason is explained in `check_server`.
In Session 7 these runs are the basis for registering the model and the alias `champion`.
The explanation in Persian is in CODE.md.
"""

import argparse
import json
import os
import pathlib

import joblib
import mlflow
import pandas as pd
import requests
import yaml
from mlflow.models import infer_signature
from sklearn.metrics import f1_score, roc_auc_score

from churn.preprocess import OUT_DIR, TARGET

# Default address of the MLflow server on this laptop (host port 5050 in compose).
DEFAULT_URI = "http://localhost:5050"
# Experiment name: the logical folder that collects all runs of this project.
EXPERIMENT = "churn"


def score(model, df: pd.DataFrame, threshold: float) -> dict:
    """Compute roc_auc and f1 of `model` on `df` (unchanged since Session 5).

    roc_auc is computed from the probabilities themselves (no threshold); f1 needs a hard
    prediction, which we get by comparing the probability with the threshold.

    Args:
        model: trained model with `predict_proba`.
        df: test table that includes the target column.
        threshold: threshold that turns a probability into a 0/1 prediction.

    Returns:
        A dict `{"roc_auc": ..., "f1": ...}`.
    """
    X, y = df.drop(columns=[TARGET]), df[TARGET]
    # The second column of predict_proba = probability that the customer churns.
    proba = model.predict_proba(X)[:, 1]
    return {
        "roc_auc": round(roc_auc_score(y, proba), 4),
        "f1": round(f1_score(y, proba > threshold), 4),
    }


def flatten(d: dict, prefix: str = "") -> dict:
    """{'train': {'C': 0.1}} -> {'train.C': 0.1}

    MLflow accepts parameters only as flat "name: value" pairs, but `params.yaml` is nested
    (the train section holds C and max_iter). This function joins the nested parts with a
    dot: `train.C`. It is recursive: it calls itself for inner dicts, so it works at any
    depth.

    Args:
        d: a dict that may be nested.
        prefix: prefix for the key names; used only in the recursive calls.

    Returns:
        A flat dict with dotted keys.
    """
    out = {}
    for key, value in d.items():
        # f-string: prefix + key name, for example "train." + "C" -> "train.C"
        name = f"{prefix}{key}"
        if isinstance(value, dict):
            # The value is a dict itself: flatten it again and add the result to out.
            out.update(flatten(value, f"{name}."))
        else:
            out[name] = value
    return out


def data_md5(raw_path: str) -> str:
    """The md5 that DVC recorded for the raw data (in data/raw/churn.csv.dvc).

    For every data version DVC records a fingerprint (md5) in the file `churn.csv.dvc`. We
    put it in the run as a tag, so later we know which data version built this model
    (data + code + parameters tracked together). If the `.dvc` file is missing (for example
    in a test) it returns `"unknown"` and does not raise an error.

    Args:
        raw_path: path of the raw data, e.g. `data/raw/churn.csv` (from params.yaml).

    Returns:
        The md5 string or `"unknown"`.
    """
    # Add the ".dvc" suffix to the data path to get the DVC pointer file.
    dvc_file = pathlib.Path(raw_path + ".dvc")
    if not dvc_file.exists():
        return "unknown"
    # A .dvc file is YAML: outs is a list and its first element is our data.
    return yaml.safe_load(dvc_file.read_text())["outs"][0]["md5"]


def tracking_uri() -> str:
    """Return the MLflow server address: env var `MLFLOW_TRACKING_URI` or the default.

    We read the address from an environment variable (the `.env` file) so we can connect to
    another server without changing the code; for example the tests point it to a
    temporary SQLite file.
    """
    return os.environ.get("MLFLOW_TRACKING_URI", DEFAULT_URI)


def check_server(uri: str) -> None:
    """Fail fast with a clear message instead of letting MLflow retry for minutes.

    If the MLflow server is off, MLflow itself retries for minutes and the student sees only
    a long, confusing error. So first we send a simple request to `/health` (at most 3
    seconds) and, if there is a problem, stop with a clear message.
    More important: if we silently skipped logging, `dvc repro` would succeed but the run
    would be lost, and since DVC sees no change next time, evaluate would not run again; so
    an error is better.

    Args:
        uri: the tracking address. If it does not start with http (for example `sqlite:///...`
            in tests) there is no HTTP server and the check is skipped.

    Raises:
        SystemExit: if the server is not reachable; the message tells the command that
            starts the server.
    """
    if not uri.startswith("http"):
        return
    try:
        # raise_for_status raises an exception if the response code is an error (such as 500).
        requests.get(f"{uri}/health", timeout=3).raise_for_status()
    except requests.RequestException as e:
        # SystemExit with a string: the program stops with this message, no long traceback.
        # `from e` links the original cause of the error to the new exception.
        raise SystemExit(
            f"MLflow server not reachable at {uri} ({type(e).__name__}).\n"
            "Start it: cd ~/mlops-lab/compose && docker compose up -d seaweedfs mlflow"
        ) from e


def log_run(model, df: pd.DataFrame, p: dict, metrics: dict, config: str) -> str:
    """Log params, metrics, tags and artifacts of this evaluation. Returns the run id.

    This function is the core of Session 6. It creates a run in MLflow and records inside it:
      - params: settings (C, threshold, seed...) so we know which settings gave the result
      - metrics: the evaluation numbers (roc_auc and f1)
      - tag `data_md5`: the data version
      - artifacts: the files `metrics.json` and `params.yaml`, and the model itself
        (with a signature)
    Together this means every experiment can be viewed and repeated later.

    Args:
        model: trained model (Pipeline).
        df: test table; the example input and the model signature are built from it.
        p: content of params.yaml as a dict.
        metrics: output of `score`.
        config: path of params.yaml so it can be saved as an artifact.

    Returns:
        The run id (a hex string); with it you can find the run in the UI or with `MlflowClient`.
    """
    uri = tracking_uri()
    check_server(uri)
    # Tell the MLflow client where to write (an HTTP server, or a SQLite file in tests).
    mlflow.set_tracking_uri(uri)
    # Select the experiment; it is created if it does not exist.
    mlflow.set_experiment(EXPERIMENT)
    X = df.drop(columns=[TARGET])
    # A readable run name for the UI table, for example "C=0.1 thr=0.5".
    run_name = f"C={p['train']['C']} thr={p['eval']['threshold']}"
    # with: the run opens at the start of the block and is closed correctly at the end, even on
    # an error (FINISHED or FAILED).
    with mlflow.start_run(run_name=run_name) as run:
        # All parameters (after flatten) are stored in MLflow as strings.
        mlflow.log_params(flatten(p))
        mlflow.log_metrics(metrics)
        # MLflow records the git commit and branch by itself (tags mlflow.source.git.*)
        # So MLflow records the git commit itself and we only add the data version.
        mlflow.set_tag("data_md5", data_md5(p["data"]["raw_path"]))
        # log_artifact copies one file; the server puts it in S3 (the bucket named mlflow).
        mlflow.log_artifact("metrics.json")
        mlflow.log_artifact(config)
        # Save the model itself in MLflow format:
        #   name="model": the name of the logged model
        #   signature: names and types of the input and output columns, inferred from sample
        #     data (our output is the churn probability); later a service can detect bad input.
        #   input_example: 5 sample input rows saved next to the model.
        mlflow.sklearn.log_model(
            model,
            name="model",
            signature=infer_signature(X, model.predict_proba(X)[:, 1]),
            input_example=X.head(5),
        )
    # Return the run id after the with block closes; its info is still available.
    return run.info.run_id


def main(config: str) -> dict:
    """Score the test split, write `metrics.json`, then log the run to MLflow.

    Args:
        config: path of the YAML settings file (default `params.yaml`).

    Returns:
        The metrics dict.
    """
    p = yaml.safe_load(open(config))
    model = joblib.load("models/model.joblib")
    df = pd.read_csv(OUT_DIR / "test.csv")
    metrics = score(model, df, p["eval"]["threshold"])
    # Order matters: metrics.json is written first because log_run reads it as an artifact.
    pathlib.Path("metrics.json").write_text(json.dumps(metrics, indent=2))
    print(metrics)
    run_id = log_run(model, df, p, metrics, config)
    # run_id[:8] is the first 8 characters of the id (shortened for printing).
    print(f"mlflow: run {run_id[:8]} logged to experiment '{EXPERIMENT}' at {tracking_uri()}")
    return metrics


# Runs only when executed directly (`python -m churn.evaluate`, or through dvc.yaml).
if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default="params.yaml")
    main(ap.parse_args().config)

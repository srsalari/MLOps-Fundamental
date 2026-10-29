"""Tests for the MLflow tracking code in churn/evaluate.py (flatten, check_server, log_run).

Session 6 (MLflow Tracking) file, added to the `tests/` folder. Important: these tests do not
need the MLflow server or Docker. Instead of a server, a temporary SQLite database is created
in pytest's temporary folder; so they run everywhere (even without internet and without compose).
Run: `make test` or `uv run pytest -q`. The `log_run` test is slower (about 20 seconds)
because saving a model in MLflow is heavy work.
The explanation in Persian is in CODE.md.
"""

import json

import mlflow
import pytest
import yaml

from churn.evaluate import check_server, flatten, log_run, score
from churn.preprocess import split
from churn.train import build_model
from make_dataset import make


def test_flatten_nested_params():
    """Nested dicts become flat dotted keys; top-level keys stay unchanged.

    MLflow does not accept nested parameters; if `flatten` breaks, the parameter names change
    in the UI (for example `train.C` disappears) and `list_runs.py` cannot find the C column.
    """
    assert flatten({"train": {"C": 0.1, "max_iter": 500}, "seed": 1}) == {
        "train.C": 0.1,
        "train.max_iter": 500,
        "seed": 1,
    }


def test_check_server_fails_fast_when_server_is_down():
    """A dead server address stops the program with a clear message (not a long hang).

    Nothing listens on port 1, so the connection is refused immediately. We expect a
    `SystemExit` whose text contains "not reachable"; `match` checks the message with a
    regex. This matters for the student: instead of waiting minutes, they see a clear message.
    """
    with pytest.raises(SystemExit, match="not reachable"):
        check_server("http://127.0.0.1:1")


def test_log_run_writes_params_metrics_and_artifacts(tmp_path, monkeypatch):
    """`log_run` stores params, metrics, the data_md5 tag, an artifact and a logged model.

    It really runs the whole logging path, but on a temporary SQLite store. pytest fixtures:
      - `tmp_path`: a unique temporary folder for this test (can be thrown away afterwards)
      - `monkeypatch`: a temporary change of the environment (current folder and an
        environment variable) that is restored automatically after the test; so it does not
        touch the student's real project and `.env`.
    """
    # a throw-away SQLite tracking store in tmp_path: no server needed
    # Go to the temporary folder so metrics.json and mlruns are not created in the real project.
    monkeypatch.chdir(tmp_path)
    # tracking_uri() reads this variable; a sqlite address means MLflow writes into a file.
    monkeypatch.setenv("MLFLOW_TRACKING_URI", f"sqlite:///{tmp_path}/mlflow.db")
    # Instead of reading the real params.yaml, build the same structure by hand.
    p = {
        "data": {"raw_path": "data/raw/churn.csv", "test_size": 0.25, "seed": 42},
        "train": {"C": 0.5, "max_iter": 200},
        "eval": {"threshold": 0.5},
    }
    # Small synthetic data (600 rows) so training is fast.
    train, test = split(make(rows=600, seed=1), 0.25, 42)
    X = train.drop(columns=["churn"])
    model = build_model(X, **p["train"]).fit(X, train["churn"])
    metrics = score(model, test, 0.5)
    # log_run reads these two files as artifacts, so they must exist in the current folder.
    (tmp_path / "metrics.json").write_text(json.dumps(metrics))
    (tmp_path / "params.yaml").write_text(yaml.safe_dump(p))

    run_id = log_run(model, test, p, metrics, "params.yaml")

    # MlflowClient reads back what was recorded; it takes the address from the same variable.
    client = mlflow.MlflowClient()
    run = client.get_run(run_id)
    # MLflow stores all parameters as strings, so "0.5" and not 0.5.
    assert run.data.params["train.C"] == "0.5"
    assert run.data.metrics["roc_auc"] == metrics["roc_auc"]
    # The file churn.csv.dvc is not in the temporary folder, so the md5 is "unknown".
    assert run.data.tags["data_md5"] == "unknown"
    # Get the list of artifacts of the run and look for metrics.json.
    assert "metrics.json" in [a.path for a in client.list_artifacts(run_id)]
    # In MLflow 3 the model is not in the run artifacts; it is recorded separately as a
    # "logged model". There must be exactly one model and its source must be this run.
    logged = client.search_logged_models(experiment_ids=[run.info.experiment_id])
    assert [m.source_run_id for m in logged] == [run_id]

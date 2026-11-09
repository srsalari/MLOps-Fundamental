"""Tests for churn/registry.py: the release gate and register -> promote.

Added in Session 7. Run them with `make test` (= `uv run pytest -q`). There are two groups:

1) Three tests for the `gate` function: only numbers and rules, no server.
2) One full test that builds a temporary MLflow (SQLite inside a tmp folder), registers
   a model (register), promotes it (promote) and checks that the aliases moved correctly.

None of them needs the real MLflow server or Docker, so they also run in CI.
"""

import json

import pytest
import yaml
from mlflow import MlflowClient

from churn.evaluate import log_run, score
from churn.preprocess import split
from churn.registry import CHALLENGER, CHAMPION, MODEL_NAME, gate, promote, register
from churn.train import build_model
from make_dataset import make

# The same three rules as the `gate` section of params.yaml (values for the tests).
RULES = {"min_roc_auc": 0.745, "min_f1": 0.69, "max_roc_auc_drop": 0.001}


def test_gate_passes_first_model_above_the_floors():
    """The first model (champion=None) passes if it is above both floors (empty list)."""
    assert gate({"roc_auc": 0.7493, "f1": 0.701}, None, RULES) == []


def test_gate_blocks_low_roc_auc_even_if_f1_is_higher():
    """A model with a better f1 but a worse roc_auc must not be promoted.

    This is the main lesson of the gate: never look at only one metric. Here two rules
    break (the roc_auc floor and the drop against the champion), so two messages return.
    """
    failed = gate({"roc_auc": 0.7358, "f1": 0.718}, {"roc_auc": 0.7493, "f1": 0.701}, RULES)
    assert len(failed) == 2
    assert failed[0].startswith("roc_auc 0.7358 < min_roc_auc")


def test_gate_allows_a_small_drop_against_the_champion():
    """A very small roc_auc drop (up to `max_roc_auc_drop`) is fine, a bigger one is not."""
    champion = {"roc_auc": 0.7493, "f1": 0.701}
    # 0.7493 - 0.001 = 0.7483 is the floor: 0.7489 is above it, 0.7480 is below it
    assert gate({"roc_auc": 0.7489, "f1": 0.7033}, champion, RULES) == []
    assert gate({"roc_auc": 0.7480, "f1": 0.7033}, champion, RULES) != []


@pytest.fixture
def one_run(tmp_path, monkeypatch):
    """Create a real MLflow run in a temporary folder and return (run_id, metrics).

    `tmp_path` is a temporary folder that pytest creates and deletes later. `monkeypatch`
    lets us change the current folder and an environment variable for this test only;
    they are restored automatically afterwards. Result: the tests never touch your real
    data or your real MLflow.
    """
    # a throw-away SQLite tracking store + registry in tmp_path: no server needed
    monkeypatch.chdir(tmp_path)  # log_run reads/writes relative files (metrics.json...)
    monkeypatch.setenv("MLFLOW_TRACKING_URI", f"sqlite:///{tmp_path}/mlflow.db")
    p = {
        "data": {"raw_path": "data/raw/churn.csv", "test_size": 0.25, "seed": 42},
        "train": {"C": 0.5, "max_iter": 200},
        "eval": {"threshold": 0.5},
    }
    # 600 synthetic rows (seed=1) are enough for a quick, deterministic model
    train, test = split(make(rows=600, seed=1), 0.25, 42)
    X = train.drop(columns=["churn"])
    model = build_model(X, **p["train"]).fit(X, train["churn"])  # **dict -> C=..., max_iter=...
    metrics = score(model, test, 0.5)
    (tmp_path / "metrics.json").write_text(json.dumps(metrics))
    (tmp_path / "params.yaml").write_text(yaml.safe_dump(p))
    return log_run(model, test, p, metrics, "params.yaml"), metrics


def test_register_then_promote_moves_the_aliases(one_run):
    """register must create version 1 and set @challenger; promote must set @champion.

    This test covers the whole Session 7 path: run -> model version -> challenger ->
    gate -> champion, and checks that the tags `gate` and `roc_auc` are written on the
    version.
    """
    run_id, metrics = one_run
    client = MlflowClient()  # uses MLFLOW_TRACKING_URI set by the fixture (the temp SQLite)
    mv = register(client, run_id[:8])  # the same 8-character prefix a student types in `make`
    assert int(mv.version) == 1  # first registration in a fresh registry
    assert client.get_model_version_by_alias(MODEL_NAME, CHALLENGER).run_id == run_id

    # Rules that everything passes, so this test checks the alias move, not the numbers.
    easy = {"min_roc_auc": 0.0, "min_f1": 0.0, "max_roc_auc_drop": 0.001}
    assert promote(client, easy) is True
    champion = client.get_model_version_by_alias(MODEL_NAME, CHAMPION)
    assert int(champion.version) == 1
    assert champion.tags["gate"] == "passed"
    # Tags are always strings, so compare with str(metric).
    assert champion.tags["roc_auc"] == str(metrics["roc_auc"])

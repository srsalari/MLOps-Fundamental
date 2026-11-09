"""API tests with a small local model: no MLflow server needed.

Added in Session 8. Run them with `make test`. The main trick: `create_app(loader=...)`
lets us pass a small local model instead of loading one from MLflow. `TestClient`
simulates HTTP requests without starting a real server (uvicorn). So the tests are fast
and need no Docker, network or MLflow.

What is tested: `/health` and `/ready`, the answer of `/predict`, rejecting bad input
with status 422, the "model failed to load" case (503), the counter in `/metrics`, the
input contract against the model signature (`contract_mismatches`), and loading a model
from the Registry by alias and by version number.
"""

import json

import pytest
import yaml
from fastapi.testclient import TestClient
from mlflow import MlflowClient

from churn.api import contract_mismatches, create_app, load_registered_model
from churn.evaluate import log_run, score
from churn.preprocess import split
from churn.registry import register
from churn.train import build_model
from make_dataset import make

# A valid request body (same shape as `Customer` in churn/api.py).
CUSTOMER = {
    "tenure_months": 3,
    "monthly_charges": 95.5,
    "contract": "month-to-month",
    "internet_service": "fiber",
    "payment_method": "card",
    "support_calls": 4,
}
# What MLflow reports as the model signature: column names and MLflow types.
SIGNATURE = [
    {"name": "tenure_months", "type": "double"},
    {"name": "monthly_charges", "type": "double"},
    {"name": "contract", "type": "string"},
    {"name": "internet_service", "type": "string"},
    {"name": "payment_method", "type": "string"},
    {"name": "support_calls", "type": "long"},
]


@pytest.fixture(scope="module")
def model():
    """A small sklearn model, trained once for the whole test file.

    `scope="module"` means pytest runs this fixture only once and shares the result
    between all tests in this file; training in every test would waste time.
    """
    train, _ = split(make(rows=600, seed=1), 0.25, 42)
    X = train.drop(columns=["churn"])
    return build_model(X, C=0.1, max_iter=200).fit(X, train["churn"])


@pytest.fixture
def client(model):
    """A TestClient that starts the API with the local model above (fake version "7").

    Every test gets a fresh app (the default scope is function), so counters and state
    do not leak between tests. `yield` means the test runs at this point, and the
    TestClient is closed after it.
    """
    # loader is a lambda: it ignores the real registry and returns our local model plus
    # a fake info dict (version "7") that we can recognise in the assertions.
    app = create_app(loader=lambda uri: (model, {"uri": uri, "version": "7", "run_id": "local"}))
    with TestClient(app) as c:  # "with" runs the startup (lifespan) that loads the model
        yield c


def test_health_and_ready(client):
    """Both health endpoints answer 200 when the model is loaded; /ready shows the version."""
    assert client.get("/health").json() == {"status": "ok"}
    assert client.get("/ready").json() == {"status": "ready", "model_version": "7"}


def test_predict_returns_a_probability(client):
    """/predict must return a probability in [0, 1], a matching decision and the model version."""
    r = client.post("/predict", json=CUSTOMER)
    assert r.status_code == 200
    body = r.json()
    assert 0 <= body["churn_probability"] <= 1
    # the decision must follow the same rule as evaluate.py: probability > threshold (0.5)
    assert body["churn"] == (body["churn_probability"] > 0.5)
    assert body["model_version"] == "7"


# parametrize runs the test below once per item: 4 bad inputs, 4 separate test results.
@pytest.mark.parametrize(
    "change",
    [
        {"contract": "weekly"},  # not one of the 3 known values
        {"support_calls": 1.5},  # long in the signature
        {"tenure_months": -1},  # out of range
        {"discount": 10},  # unknown field
    ],
)
def test_bad_input_is_rejected_with_422(client, change):
    """Invalid input must be rejected with 422 before it reaches the model.

    `{**CUSTOMER, **change}` is a copy of the valid customer with exactly one field broken
    (the keys of `change` overwrite the old values).
    """
    assert client.post("/predict", json={**CUSTOMER, **change}).status_code == 422


def test_missing_field_is_rejected(client):
    """A missing field gives 422, and the error says exactly which field is missing."""
    # dict comprehension: a copy of CUSTOMER without the "contract" key
    body = {k: v for k, v in CUSTOMER.items() if k != "contract"}
    r = client.post("/predict", json=body)
    assert r.status_code == 422
    # FastAPI's error list says where the problem is: in the body, field "contract"
    assert r.json()["detail"][0]["loc"] == ["body", "contract"]


def test_not_ready_when_the_model_cannot_be_loaded():
    """If loading the model fails, the service must stay alive but not be ready.

    That means `/health` is 200 and `/ready` and `/predict` are 503. The fake loader
    raises `SystemExit` because the real `connect()` and `check_download_setting()` do
    the same; the test proves that lifespan catches it and the server does not die.
    """

    def broken(uri):
        raise SystemExit("MLflow server not reachable")

    with TestClient(create_app(loader=broken)) as c:  # "with" = run the startup (lifespan)
        assert c.get("/health").status_code == 200
        assert c.get("/ready").status_code == 503
        assert c.post("/predict", json=CUSTOMER).status_code == 503


def test_metrics_count_predictions(client):
    """Every successful /predict must raise `churn_predictions_total` by exactly one.

    Prometheus counters stay in the memory of this process between tests, so we compare
    the value "before" and "after", not an absolute number.
    """

    def predictions(text):
        """Sum of all churn_predictions_total{churn="true"/"false"} lines in /metrics text."""
        lines = [x for x in text.splitlines() if x.startswith("churn_predictions_total{")]
        # each line looks like: churn_predictions_total{churn="true"} 3.0 -> take the last word
        return sum(float(x.split()[-1]) for x in lines)

    before = predictions(client.get("/metrics").text)
    client.post("/predict", json=CUSTOMER)
    text = client.get("/metrics").text
    assert predictions(text) == before + 1
    assert "http_requests_total" in text  # request counters of prometheus-fastapi-instrumentator


def test_contract_matches_the_model_signature():
    """`Customer` matches the signature, and a changed column type is detected."""
    assert contract_mismatches(SIGNATURE) == []
    # [*a, b] = a new list: the first five columns plus one changed column (long -> double)
    wrong = [*SIGNATURE[:5], {"name": "support_calls", "type": "double"}]
    assert contract_mismatches(wrong) == ["field 'support_calls' is int, signature says double"]


def test_load_registered_model_by_alias_and_by_version(tmp_path, monkeypatch):
    """Both URI forms (`@alias` and `/version`) must load the same version 1 and the same run.

    This test builds a temporary SQLite Registry (no server), registers one model (register
    sets the alias `@challenger`) and then calls `load_registered_model`. We also set
    `MLFLOW_ENABLE_PROXY_MULTIPART_DOWNLOAD=false` because the function checks it.
    """
    # a throw-away SQLite registry in tmp_path with one version and alias @challenger
    monkeypatch.chdir(tmp_path)
    monkeypatch.setenv("MLFLOW_TRACKING_URI", f"sqlite:///{tmp_path}/mlflow.db")
    # without this variable load_registered_model stops with SystemExit (see registry.py)
    monkeypatch.setenv("MLFLOW_ENABLE_PROXY_MULTIPART_DOWNLOAD", "false")
    p = {"data": {"raw_path": "x.csv"}, "train": {"C": 0.5}, "eval": {"threshold": 0.5}}
    train, test = split(make(rows=600, seed=1), 0.25, 42)
    X = train.drop(columns=["churn"])
    model = build_model(X, C=0.5, max_iter=200).fit(X, train["churn"])
    (tmp_path / "metrics.json").write_text(json.dumps(score(model, test, 0.5)))
    (tmp_path / "params.yaml").write_text(yaml.safe_dump(p))
    run_id = log_run(model, test, p, score(model, test, 0.5), "params.yaml")
    register(MlflowClient(), run_id[:8])

    # one loop, two URI styles: by alias and by explicit version number
    for uri in ("models:/churn@challenger", "models:/churn/1"):
        loaded, info = load_registered_model(uri)
        assert info["version"] == "1" and info["run_id"] == run_id
        # 3 rows in -> a (3, 2) array out: two probabilities (stay, churn) per row
        assert loaded.predict_proba(test.drop(columns=["churn"]).head(3)).shape == (3, 2)

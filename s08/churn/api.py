"""Inference API: serves the @champion model of the MLflow Model Registry over REST.

Run:  uv run uvicorn churn.api:app --port 8000

Added in Session 8. It turns the model we made `@champion` in Session 7 into a web
service (REST API). Any other program (website, mobile app, ...) can send the details of
one customer over HTTP and receive the churn probability in the answer.

Run (from the project root, with the MLflow server running and the `.env` variables loaded):

    make serve          (= `uv run uvicorn churn.api:app --host 127.0.0.1 --port 8000`)

Endpoints (the addresses the service offers):

    GET  /health      the process is alive (liveness)
    GET  /ready       the model is loaded (readiness): status 503 if it is not loaded
    GET  /model-info  version and run_id of the model that is served right now
    POST /predict     input: one customer (JSON), output: the churn probability
    GET  /metrics     Prometheus metrics (used for monitoring in later sessions)
    GET  /docs        interactive documentation that FastAPI builds automatically

Important parts of this file:

1) `Customer`: the "input contract". pydantic checks every request before it reaches the
   model and answers status 422 by itself when a type or a range is wrong.
2) `load_registered_model`: resolves the alias to a version number only once and loads
   exactly that version.
3) `create_app(loader)`: builds the service. The function that loads the model is passed
   in from outside, so tests can give a small local model and need no MLflow server.
4) `lifespan`: work done once when the server starts (loading the model). If loading
   fails, the service does not shut down; it stays alive but "not ready".
5) JSON logs, a counter and a histogram for Prometheus.

Connection to other sessions: it uses `churn/registry.py` (Session 7) to connect to
MLflow. In later sessions this same code goes into a Docker image and then onto Kubernetes.
"""

import json
import logging
import os
import time
from collections.abc import Callable
from contextlib import asynccontextmanager
from typing import Literal

import mlflow
import pandas as pd
from fastapi import FastAPI, HTTPException, Request
from prometheus_client import Counter, Histogram
from prometheus_fastapi_instrumentator import Instrumentator
from pydantic import BaseModel, ConfigDict, Field

from churn.registry import check_download_setting, connect

# Config comes from environment variables with defaults, so the same code runs on the
# laptop, in Docker and in Kubernetes without editing the file (12-factor style).
MODEL_URI = os.environ.get("MODEL_URI", "models:/churn@champion")
THRESHOLD = float(os.environ.get("PREDICT_THRESHOLD", "0.5"))  # env values are always str

# Prometheus metrics live at module level: they must be created ONCE per process.
# Counter only goes up. The label "churn" ("true"/"false") splits it into two series.
PREDICTIONS = Counter("churn_predictions_total", "Predictions served", ["churn"])
# Histogram counts how many observations fell into time buckets (to see slow requests).
LATENCY = Histogram("churn_predict_seconds", "Time spent in model.predict_proba")


class JsonFormatter(logging.Formatter):
    """One JSON object per log line: easy to search and to ship to a log system.

    Why JSON? Plain text logs are only for humans, but tools like Loki or Elasticsearch
    understand JSON logs field by field, so you can search for example all requests with
    `status=500`. A `Formatter` in Python decides how each log record is turned into text.
    """

    def format(self, record: logging.LogRecord) -> str:
        """Turn one log record into a JSON string (called by logging for every message)."""
        entry = {"ts": self.formatTime(record), "level": record.levelname, "event": record.msg}
        # We pass extra fields as log.info("x", extra={"fields": {...}}); logging stores
        # them as record.fields. getattr(..., {}) = empty dict when a log has no extras.
        entry.update(getattr(record, "fields", {}))
        return json.dumps(entry)


# Logger setup: a named logger -> one handler (stderr) with our JSON format.
log = logging.getLogger("churn.api")
_handler = logging.StreamHandler()
_handler.setFormatter(JsonFormatter())
log.addHandler(_handler)
log.setLevel(logging.INFO)  # INFO and above (INFO, WARNING, ERROR) are printed
log.propagate = False  # do not also send records to the root logger (no duplicate lines)


# One valid request body. It is shown as an example in the /docs page (see Customer below).
EXAMPLE = {
    "tenure_months": 3,
    "monthly_charges": 95.5,
    "contract": "month-to-month",
    "internet_service": "fiber",
    "payment_method": "card",
    "support_calls": 4,
}


class Customer(BaseModel):
    """Input contract. Field names and types must match the model signature.

    This class defines the shape of a `/predict` request. pydantic compares every incoming
    JSON with it: a missing or extra field, a wrong type or a number out of range gives
    status 422 (Unprocessable Entity) and the model is not called at all. So bad data never
    reaches the model.
    """

    # extra="forbid": an unknown field (e.g. "discount") is an error, not silently ignored.
    # json_schema_extra: puts EXAMPLE in the /docs page so "Try it out" is pre-filled.
    model_config = ConfigDict(extra="forbid", json_schema_extra={"examples": [EXAMPLE]})

    # Field(ge=0, le=120): "greater or equal 0" and "less or equal 120" (a sanity range).
    tenure_months: float = Field(ge=0, le=120)
    monthly_charges: float = Field(gt=0, le=500)  # gt = strictly greater than 0
    # Literal[...]: only these exact strings are accepted (a closed set of categories).
    contract: Literal["month-to-month", "one-year", "two-year"]
    internet_service: Literal["dsl", "fiber", "none"]
    payment_method: Literal["card", "bank_transfer", "cash"]
    support_calls: int = Field(ge=0, le=50)  # int: 1.5 is rejected (the signature says long)


class Prediction(BaseModel):
    """Response body of `/predict`: the probability, the decision and which model made it.

    The model version is part of the answer, so if @champion changes later we can tell
    which version gave each prediction.
    """

    churn_probability: float
    churn: bool
    threshold: float
    model_version: str


# MLflow signature type -> Python type of the pydantic field
SIGNATURE_TYPES = {"double": float, "float": float, "long": int, "integer": int, "string": str}


def contract_mismatches(signature_inputs: list[dict]) -> list[str]:
    """Compare Customer with the model signature ([{'name':..., 'type':...}, ...]).

    The model signature is the list of columns and the type of each column. This function
    finds three kinds of mismatch: 1) a column exists in the model but not in `Customer`.
    2) the field type differs from the column type (for example int against double).
    3) `Customer` has a field the model does not know.

    Args:
        signature_inputs: list of dicts with "name" and "type" (from signature.inputs.to_dict()).

    Returns:
        List of problem descriptions; empty list means API and model agree.
    """
    problems = []
    # dict comprehension: {"tenure_months": float, ..., "contract": Literal[...]}
    fields = {name: f.annotation for name, f in Customer.model_fields.items()}
    for col in signature_inputs:
        # SIGNATURE_TYPES.get(...) gives None for a type we do not know (always a mismatch)
        name, expected = col["name"], SIGNATURE_TYPES.get(col["type"])
        if name not in fields:
            problems.append(f"missing field '{name}' ({col['type']})")
            continue  # nothing to compare for this column, go to the next one
        actual = fields.pop(name)  # pop = remove, so what is left at the end is "extra"
        # A Literal[...] field is a string in JSON; its __origin__ is `Literal`.
        actual = str if getattr(actual, "__origin__", None) is Literal else actual
        if actual is not expected:
            problems.append(f"field '{name}' is {actual.__name__}, signature says {col['type']}")
    # Whatever remains in `fields` was never seen in the signature.
    problems += [f"extra field '{name}' (not in the signature)" for name in fields]
    return problems


def load_registered_model(uri: str):
    """models:/churn@champion or models:/churn/3. An alias is resolved ONCE, then exactly
    that version is loaded, so a moving alias cannot give us a mix of two versions.

    Why resolve the alias only once? An alias is a moving label. If we loaded
    `models:/churn@champion` directly and someone ran `promote` at that moment, part of
    the work could use the old version and part the new one. So we first ask which version
    number the alias points to right now, and then load exactly that number
    (`models:/churn/3`). We also keep the version number for `/model-info` and the logs.

    Args:
        uri: "models:/<name>@<alias>" or "models:/<name>/<version>".

    Returns:
        Tuple (sklearn Pipeline, info dict with uri, name, version, run_id).

    Raises:
        SystemExit: from check_download_setting / connect when the setup is wrong.
        MlflowException: when the alias or version does not exist.
    """
    check_download_setting()  # without this env variable load_model would hang forever
    client = connect()
    path = uri.removeprefix("models:/")  # "churn@champion" or "churn/3"
    if "@" in path:
        name, alias = path.split("@")  # unpack the two parts
        mv = client.get_model_version_by_alias(name, alias)  # alias -> a concrete version
    else:
        name, version = path.split("/")
        mv = client.get_model_version(name, version)
    # Load by number, not by alias: exactly the version we just resolved.
    model = mlflow.sklearn.load_model(f"models:/{name}/{mv.version}")
    return model, {"uri": uri, "name": name, "version": str(mv.version), "run_id": mv.run_id}


def create_app(loader: Callable = load_registered_model) -> FastAPI:
    """Build the FastAPI application. `loader(uri)` must return (model, info dict).

    Why is everything inside one function and why does it take `loader`? For testing. In
    tests we do not pass `load_registered_model` (which connects to MLflow) but a small
    function that returns a local model. All the other code is exactly what runs in
    production. The last line of the file builds an `app` with the real loader, and
    uvicorn runs that one.

    Args:
        loader: function taking the model URI and returning (model, info).

    Returns:
        The configured FastAPI app (not started; uvicorn or TestClient starts it).
    """

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        """Startup / shutdown hook: code before `yield` runs once when the server starts.

        Code before `yield` runs once when the server starts (here: loading the model).
        Code after it runs when the server stops (we have nothing there). We store the
        model in `app.state` so all endpoints can use it and it is not loaded again for
        every request (loading takes a few seconds).
        """
        # Start in the "not ready" state: no model yet. /ready will answer 503 until set.
        app.state.model, app.state.info = None, {"uri": MODEL_URI}
        start = time.perf_counter()  # perf_counter = accurate clock for measuring durations
        try:
            app.state.model, app.state.info = loader(MODEL_URI)
        except (Exception, SystemExit) as e:  # stay alive but NOT ready
            # SystemExit is not an Exception subclass, and check_download_setting/connect
            # raise it, so it must be listed explicitly. If we did not catch it, the whole
            # server would die; Kubernetes would restart it again and again (crash loop)
            # instead of just reporting "not ready".
            log.error("model_load_failed", extra={"fields": {"uri": MODEL_URI, "error": str(e)}})
        else:  # runs only if the try block had no exception
            secs = round(time.perf_counter() - start, 2)
            # {**a, "k": v} = a new dict with everything from a plus one more key
            log.info("model_loaded", extra={"fields": {**app.state.info, "seconds": secs}})
        yield  # the server runs (and serves requests) while we are suspended here

    app = FastAPI(title="Churn inference API", version="0.6.0", lifespan=lifespan)
    # Adds the /metrics endpoint with HTTP metrics (http_requests_total, latency...) and
    # also exposes our own PREDICTIONS / LATENCY from the default Prometheus registry.
    Instrumentator().instrument(app).expose(app, include_in_schema=False)

    @app.middleware("http")
    async def access_log(request: Request, call_next):
        """Log one JSON line per request (method, path, status, milliseconds).

        Middleware is code that runs around every request: before the endpoint, the
        endpoint itself (`call_next`), and after it. Here we only measure the time and write
        one log line after the response is ready. We do not log the request body because
        it may contain personal data of the customer.
        """
        start = time.perf_counter()
        response = await call_next(request)  # run the real endpoint and wait for its response
        ms = round((time.perf_counter() - start) * 1000, 1)  # seconds -> milliseconds
        fields = {"method": request.method, "path": request.url.path}
        log.info("request", extra={"fields": {**fields, "status": response.status_code, "ms": ms}})
        return response

    @app.get("/health")
    def health() -> dict:
        """Liveness: the process is up.

        The simple answer "I am alive". Kubernetes uses it to decide whether to restart the
        process, so it deliberately does not depend on the model: the service is alive even
        when the model is not loaded.
        """
        return {"status": "ok"}

    @app.get("/ready")
    def ready(request: Request) -> dict:
        """Readiness: the model is loaded and requests can be served.

        "Am I ready to take requests?" It answers 200 only when the model is loaded.
        Otherwise it answers 503 and Kubernetes does not send traffic to this copy (but
        it does not restart it either). The difference between `/health` and `/ready` is
        one of the important questions of the class.

        Raises:
            HTTPException: 503 if the model is not loaded.
        """
        # request.app.state: the same object the lifespan filled at startup
        if request.app.state.model is None:
            raise HTTPException(503, "model not loaded")
        return {"status": "ready", "model_version": request.app.state.info["version"]}

    @app.get("/model-info")
    def model_info(request: Request) -> dict:
        """Which model is served: uri, name, version, run_id and the decision threshold."""
        return {**request.app.state.info, "threshold": THRESHOLD}

    @app.post("/predict")
    def predict(customer: Customer, request: Request) -> Prediction:
        """Score one customer and return the churn probability and the yes/no decision.

        Note: the parameter `customer: Customer` means FastAPI reads the JSON body itself
        and checks it with pydantic; if it is wrong, this function does not run at all
        (status 422). The output is also checked with `Prediction` and turned into JSON.

        Raises:
            HTTPException: 503 if the model is not loaded.
        """
        model, info = request.app.state.model, request.app.state.info
        if model is None:
            raise HTTPException(503, "model not loaded")
        # The model expects a table: one row, columns named like in the training data.
        X = pd.DataFrame([customer.model_dump()])
        with LATENCY.time():  # records how long the block takes into the histogram
            # predict_proba -> [[P(stay), P(churn)]]; [0, 1] = first row, churn column
            proba = round(float(model.predict_proba(X)[0, 1]), 4)
        # Strictly greater: a probability exactly equal to the threshold counts as "no churn".
        churn = proba > THRESHOLD  # same rule as evaluate.py
        # Label values must be strings: True -> "true"
        PREDICTIONS.labels(churn=str(churn).lower()).inc()
        # Log only the version and the probability, not the customer's data (privacy).
        log.info("prediction", extra={"fields": {"version": info["version"], "proba": proba}})
        return Prediction(
            churn_probability=proba,
            churn=churn,
            threshold=THRESHOLD,
            model_version=info["version"],
        )

    return app


# The real app that `uvicorn churn.api:app` imports. Importing does NOT load the model:
# that happens in `lifespan`, when the server starts.
app = create_app()

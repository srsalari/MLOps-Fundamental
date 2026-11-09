# Targets that are not file names (always run them, even if a file with the same name exists).
.PHONY: data train lint test runs register promote models predict contract serve image scan push run-image
# `PORT` is the API port, default 8000 (make serve PORT=9000). ?= sets it only if it is empty.
PORT ?= 8000
# Session 9: image name and tag, local registry, and how the container reaches MLflow
# (the Docker network of ~/mlops-lab/compose and the MLflow address inside it).
IMAGE ?= churn-api
TAG ?= 0.7.0
REGISTRY ?= localhost:5001
NETWORK ?= mlops-lab
MLFLOW_IN_DOCKER ?= http://mlflow:5000
# Trivy reads its offline database from here (scripts/install-from-bundle.sh copies it there).
export TRIVY_CACHE_DIR ?= $(HOME)/.cache/trivy

# Targets from earlier sessions (1 to 6)
# `data`: build the synthetic churn dataset in data/raw/churn.csv (Session 1).
data:
	uv run python scripts/make_dataset.py

# `train`: run the whole pipeline with DVC (only changed stages run again).
train:
	uv run dvc repro

# `lint`: check style and errors with ruff, without changing any file.
lint:
	uv run ruff check .
	uv run ruff format --check .

# `test`: run all tests with pytest (-q = short output).
test:
	uv run pytest -q

# `runs`: print the MLflow runs with the first 8 characters of the id (used by register).
runs:
	uv run python scripts/list_runs.py

# Session 7: Model Registry
# `register`: register the model of one run as a new version and set @challenger.
# Example: `make register RUN=1a2b3c4d` (take RUN from `make runs`).
register:
	uv run python -m churn.registry register --run $(RUN)

# `promote`: run the gate on the challenger and, if it passes, move @champion.
promote:
	uv run python -m churn.registry promote

# `models`: print the table of churn model versions with metrics and aliases.
models:
	uv run python -m churn.registry show

# `predict`: load the @champion model from the Registry and predict 5 test rows.
predict:
	uv run python scripts/predict_champion.py

# Session 8: inference API
# `contract`: compare the API input (Customer) with the signature of the @champion model.
contract:
	uv run python scripts/check_contract.py

# `serve`: run the API with uvicorn on localhost (needs @champion and the .env variables).
# `--no-access-log` turns off uvicorn's own access log, because the API writes JSON logs.
serve:
	uv run uvicorn churn.api:app --host 127.0.0.1 --port $(PORT) --no-access-log

# Session 9: container image
# `image`: build the two-stage image (Dockerfile) as churn-api:0.7.0.
image:
	docker build -t $(IMAGE):$(TAG) .

# `scan`: Trivy with the offline database; fails (exit 1) on a HIGH/CRITICAL finding that has a fix.
scan:
	trivy image --skip-db-update --offline-scan --skip-version-check --scanners vuln \
	  --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 $(IMAGE):$(TAG)

# `run-image`: start the container next to MLflow (same Docker network) on port 8001.
run-image:
	docker run -d --name churn-api --network $(NETWORK) -p 127.0.0.1:8001:8000 \
	  -e MLFLOW_TRACKING_URI=$(MLFLOW_IN_DOCKER) $(IMAGE):$(TAG)

# `push`: copy the image to the local registry.
push:
	docker tag $(IMAGE):$(TAG) $(REGISTRY)/$(IMAGE):$(TAG)
	docker push $(REGISTRY)/$(IMAGE):$(TAG)

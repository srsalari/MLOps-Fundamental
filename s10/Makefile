# Targets that are not file names (always run them, even if a file with the same name exists).
.PHONY: data train lint test runs register promote models predict contract serve image scan push run-image \
	vm-image vm-up vm-ssh release deploy rollback
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
# Session 10: the practice VM (a container with systemd + SSH) and how Ansible reaches it.
VM_NAME ?= mlops-vm
VM_IMAGE ?= mlops/practice-vm:24.04
VM_DIR ?= $(HOME)/mlops-lab/s10/vm
VM_SSH_PORT ?= 2223
VM_HTTP_PORT ?= 8090
VM_KEY ?= $(HOME)/.ssh/mlops_vm
KNOWN_HOSTS ?= $(HOME)/.ssh/known_hosts

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

# Session 10: deploy to a VM with Ansible
# `vm-image`: build the practice VM image (Ubuntu 24.04 + systemd + SSH) from the course repo.
vm-image:
	docker build -t $(VM_IMAGE) $(VM_DIR)

# `vm-up`: start the VM on the lab network, create an SSH key once and install it in the VM.
vm-up:
	docker run -d --name $(VM_NAME) --hostname $(VM_NAME) --privileged --network $(NETWORK) \
	  -p 127.0.0.1:$(VM_SSH_PORT):22 -p 127.0.0.1:$(VM_HTTP_PORT):80 $(VM_IMAGE)
	test -f $(VM_KEY) || ssh-keygen -q -t ed25519 -N "" -C mlops-vm -f $(VM_KEY)
	docker cp $(VM_KEY).pub $(VM_NAME):/home/ubuntu/.ssh/authorized_keys
	docker exec $(VM_NAME) chown ubuntu:ubuntu /home/ubuntu/.ssh/authorized_keys
	ssh-keygen -R "[127.0.0.1]:$(VM_SSH_PORT)" -f $(KNOWN_HOSTS) >/dev/null 2>&1 || true

# `vm-ssh`: log in to the VM as user ubuntu.
vm-ssh:
	ssh -i $(VM_KEY) -p $(VM_SSH_PORT) -o UserKnownHostsFile=$(KNOWN_HOSTS) -o StrictHostKeyChecking=accept-new ubuntu@127.0.0.1

# `release`: build the app wheel and the pinned list of libraries for the VM.
release:
	rm -rf dist
	uv build --wheel
	uv export -q --no-dev --no-emit-project --no-hashes --format requirements-txt -o deploy/requirements.txt

# `deploy`: run the Ansible playbook (installs or updates the service on the VM).
deploy: release
	cd deploy && uv run ansible-playbook deploy.yml -e ansible_port=$(VM_SSH_PORT) --private-key $(VM_KEY)

# `rollback`: deploy again, but serve an older model version: make rollback VERSION=1
rollback:
	cd deploy && uv run ansible-playbook deploy.yml -e ansible_port=$(VM_SSH_PORT) --private-key $(VM_KEY) \
	  -e model_uri=models:/churn/$(VERSION)

# Targets that are not file names (always run them, even if a file with the same name exists).
.PHONY: data train lint test runs register promote models predict contract serve image scan push run-image \
	vm-image vm-up vm-ssh release deploy rollback k8s-up k8s-deploy k8s-status k8s-forward \
	ingress-up ingress-apply helm-lint helm-template helm-deploy helm-status helm-rollback helm-uninstall \
	runner-up mon-up mon-down mon-status api-break api-fix load drift \
	demo-check readiness
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
# Session 11: the kind cluster. Every kubectl command names the context, so it never
# touches another cluster in your kubeconfig by mistake.
CLUSTER ?= mlops
KCTX ?= kind-$(CLUSTER)
KUBECTL = kubectl --context $(KCTX)
LAB_DIR ?= $(HOME)/mlops-lab
FORWARD_PORT ?= 8002
# Session 12: Traefik (Ingress) and Helm. Every helm command names the context too.
HELM = helm --kube-context $(KCTX)
TRAEFIK_CHART ?= $(LAB_DIR)/charts/traefik-41.5.0.tgz
TRAEFIK_VALUES ?= $(LAB_DIR)/k8s/traefik-values.yaml
CHART ?= chart/churn-api
RELEASE ?= churn-api
# STAGE picks the values file (dev or prod). NS is the namespace of the release.
STAGE ?= dev
NS ?= churn
# Extra helm options, for example: make helm-deploy HELM_ARGS="--set replicaCount=3"
HELM_ARGS ?=
# Session 13: CI, monitoring and drift.
# The monitoring stack (Prometheus, Grafana and one API container) is described in monitoring/.
MON = docker compose -f monitoring/docker-compose.yml
API_URL ?= http://localhost:8003
PROM_URL ?= http://localhost:9090
# Traffic generator: requests per second, how long, and the share of wrong requests (0 to 1).
RPS ?= 5
DURATION ?= 60
BAD ?= 0

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
	-ssh-keygen -R "[127.0.0.1]:$(VM_SSH_PORT)" -f $(KNOWN_HOSTS) 2>/dev/null

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

# Session 11: Kubernetes on kind
# `k8s-up`: create the registry + cluster (course script) and connect the node to the lab network
# so pods reach MLflow as http://mlflow:5000.
k8s-up:
	$(LAB_DIR)/scripts/kind-up.sh
	docker network connect $(NETWORK) $(CLUSTER)-control-plane 2>/dev/null || true

# `k8s-deploy`: apply the manifests in k8s/ and wait until all pods are ready.
k8s-deploy:
	$(KUBECTL) apply -f k8s/namespace.yaml
	$(KUBECTL) apply -f k8s/
	$(KUBECTL) -n churn rollout status deployment/churn-api --timeout=180s

# `k8s-status`: what is running (pods, ReplicaSets, service) and the rollout history.
k8s-status:
	$(KUBECTL) -n churn get deploy,rs,pods,svc
	$(KUBECTL) -n churn rollout history deployment/churn-api

# `k8s-forward`: reach the service from the laptop on http://localhost:8002 (Ctrl+C stops it).
k8s-forward:
	$(KUBECTL) -n churn port-forward svc/churn-api $(FORWARD_PORT):80

# Session 12: Ingress with Traefik and a Helm chart
# `ingress-up`: install (or upgrade) Traefik from the offline chart; NodePorts 30080/30443 -> laptop 8080/8443.
ingress-up:
	$(HELM) upgrade --install traefik $(TRAEFIK_CHART) -n traefik --create-namespace \
	  -f $(TRAEFIK_VALUES) --wait --timeout 120s

# `ingress-apply`: apply the plain Ingress (k8s/ingress.yaml) for churn.localhost.
ingress-apply:
	$(KUBECTL) apply -f k8s/ingress.yaml

# `helm-lint`: check the chart for mistakes (no cluster needed).
helm-lint:
	$(HELM) lint $(CHART) -f $(CHART)/values-$(STAGE).yaml

# `helm-template`: print the YAML the chart makes for STAGE (no cluster change).
helm-template:
	$(HELM) template $(RELEASE) $(CHART) -n $(NS) -f $(CHART)/values-$(STAGE).yaml $(HELM_ARGS)

# `helm-deploy`: install or upgrade the release with the values of STAGE, wait until ready.
helm-deploy:
	$(HELM) upgrade --install $(RELEASE) $(CHART) -n $(NS) --create-namespace \
	  -f $(CHART)/values-$(STAGE).yaml --wait --timeout 120s $(HELM_ARGS)

# `helm-status`: the release, its history, and what runs in the namespace.
helm-status:
	$(HELM) list -n $(NS)
	$(HELM) history $(RELEASE) -n $(NS)
	$(KUBECTL) -n $(NS) get deploy,pods,svc,ingress

# `helm-rollback`: go back to a revision: make helm-rollback REV=2
helm-rollback:
	$(HELM) rollback $(RELEASE) $(REV) -n $(NS) --wait --timeout 120s

# `helm-uninstall`: remove the release (the namespace stays).
helm-uninstall:
	$(HELM) uninstall $(RELEASE) -n $(NS)

# Session 13: CI, monitoring, drift
# `runner-up`: start the Gitea Actions runner of the lab (compose profile "ci").
runner-up:
	cd $(LAB_DIR)/compose && docker compose --profile ci up -d gitea-runner

# `mon-up`: start Prometheus (9090), Grafana (3001) and the API for monitoring (8003).
mon-up:
	$(MON) up -d

# `mon-down`: stop them (the data stays; never add -v in class).
mon-down:
	$(MON) down

# `mon-status`: containers of the monitoring stack and the state of the Prometheus targets.
mon-status:
	$(MON) ps
	@curl -s $(PROM_URL)/api/v1/targets | python3 -c "import json,sys; [print(t['labels']['job'], t['health']) for t in json.load(sys.stdin)['data']['activeTargets']]"

# `api-break`: restart the API with a model that does not exist: /predict answers 503.
api-break:
	MODEL_URI=models:/churn/99 $(MON) up -d churn-api-mon

# `api-fix`: restart the API with the normal @champion model.
api-fix:
	$(MON) up -d churn-api-mon

# `load`: send fake traffic: make load RPS=10 DURATION=120 BAD=0.1
load:
	uv run python scripts/loadgen.py --url $(API_URL) --rps $(RPS) --seconds $(DURATION) --bad-rate $(BAD)

# `drift`: Evidently report, data v1 against data v2 -> reports/drift-v1-v2.html
drift:
	uv run --group drift python scripts/drift_report.py

# Session 14: capstone
# Where the service answers (through Traefik) and the other URLs the demo needs.
SERVICE_URL ?= http://churn.localhost:8080
GRAFANA_URL ?= http://localhost:3001
# `demo-check`: run it 10 minutes before the demo. Are the service, Prometheus and Grafana up,
# and what is the readiness score? (QUICK=1 skips pytest and Trivy, so it takes about 10 seconds.)
demo-check:
	@echo "== demo check =="
	@curl -fsS --max-time 5 $(SERVICE_URL)/ready >/dev/null && echo "service     OK    $(SERVICE_URL)" || echo "service     DOWN $(SERVICE_URL)   (make helm-status)"
	@curl -fsS --max-time 5 $(PROM_URL)/-/ready >/dev/null && echo "prometheus  OK    $(PROM_URL)" || echo "prometheus  DOWN  $(PROM_URL)   (make mon-up)"
	@curl -fsS --max-time 5 $(GRAFANA_URL)/api/health >/dev/null && echo "grafana     OK    $(GRAFANA_URL)" || echo "grafana     DOWN  $(GRAFANA_URL)   (make mon-up)"
	@QUICK=1 scripts/readiness_check.sh | tail -8

# `readiness`: the full score (runs pytest and the Trivy scan too, about 40 seconds).
readiness:
	scripts/readiness_check.sh

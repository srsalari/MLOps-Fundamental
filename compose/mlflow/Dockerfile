# Minimal MLflow tracking server with S3 (SeaweedFS) artifact support (sessions 6-8).
# Built by compose/docker-compose.yml (service "mlflow"); versions are passed as build args.
ARG PYTHON_BASE_IMAGE=python:3.12-slim-bookworm
FROM ${PYTHON_BASE_IMAGE}
# Pinned versions: the same MLflow as the students' Python environment.
ARG MLFLOW_VERSION=3.17.2
ARG BOTO3_VERSION=1.43.95
# PIP_INDEX_URL / PIP_FIND_LINKS can point at the classroom mirror or a wheelhouse when offline
RUN pip install --no-cache-dir "mlflow==${MLFLOW_VERSION}" "boto3==${BOTO3_VERSION}" \
 && useradd --uid 1000 --create-home mlflow && mkdir /mlflow && chown mlflow /mlflow
# Run as a normal user (uid 1000), not root. /mlflow holds mlflow.db (the volume).
USER mlflow
WORKDIR /mlflow
# Documentation only: the server (started by compose) listens on 5000.
EXPOSE 5000

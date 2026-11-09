# Session 9: the churn API in a small, non-root image (two stages).

# ---- stage 1: build the virtual environment with uv ----
FROM python:3.12-slim-bookworm AS build
COPY --from=ghcr.io/astral-sh/uv:0.12.15 /uv /usr/local/bin/uv
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy UV_PYTHON_DOWNLOADS=never
WORKDIR /app
# Dependencies first: this layer is reused while pyproject.toml/uv.lock do not change.
COPY pyproject.toml uv.lock README.md ./
RUN uv sync --frozen --no-dev --no-install-project
# Then our own code.
COPY src ./src
RUN uv sync --frozen --no-dev --no-editable

# ---- stage 2: runtime, only Python + the venv ----
FROM python:3.12-slim-bookworm AS runtime
RUN useradd --create-home --uid 10001 app
WORKDIR /app
COPY --from=build --chown=app:app /app/.venv /app/.venv
ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    MLFLOW_ENABLE_PROXY_MULTIPART_DOWNLOAD=false \
    MLFLOW_ENABLE_ARTIFACTS_PROGRESS_BAR=false \
    MLFLOW_DISABLE_AGENT_HINT=1
USER app
EXPOSE 8000
HEALTHCHECK --interval=10s --timeout=3s --start-period=20s --retries=3 \
  CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=2)"]
CMD ["uvicorn", "churn.api:app", "--host", "0.0.0.0", "--port", "8000", "--no-access-log"]

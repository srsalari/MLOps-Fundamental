# This Makefile holds shortcuts; in Session 6 a new target, `runs`, is added.
# Warning: recipe lines (the commands) must start with a TAB character, not spaces.

# These are names of jobs, not files; .PHONY makes make always run them.
.PHONY: data train lint test runs

# Create the synthetic data in data/raw/churn.csv (versioned with DVC in Session 4).
data:
	uv run python scripts/make_dataset.py

# Run the pipeline with DVC. From Session 6 the evaluate stage also logs a run to MLflow
# every time, so the MLflow server must be running.
train:
	uv run dvc repro

# Code quality: ruff check for errors and style, ruff format --check for consistent formatting.
lint:
	uv run ruff check .
	uv run ruff format --check .

# Run the unit tests; they do not need the MLflow server.
test:
	uv run pytest -q

# Print a table of the runs of the experiment named churn in the terminal (newest first).
runs:
	uv run python scripts/list_runs.py

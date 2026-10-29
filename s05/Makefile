# This Makefile holds shortcuts; in Session 5 the `train` target is handed over to DVC.
# Warning: recipe lines (the commands) must start with a TAB character, not spaces.

# These are names of jobs, not files; .PHONY makes make always run them.
.PHONY: data train lint test

# Create the synthetic data in data/raw/churn.csv (versioned with DVC in Session 4).
data:
	uv run python scripts/make_dataset.py

# Run the whole pipeline (preprocess, train, evaluate) with DVC. Only stages whose inputs
# changed run again; the rest come from the cache. Results: models/ and metrics.json.
train:
	uv run dvc repro

# Code quality: errors and style (ruff check), then consistent formatting (ruff format --check).
lint:
	uv run ruff check .
	uv run ruff format --check .

# Run the unit tests with pytest in quiet mode (-q).
test:
	uv run pytest -q

"""Stage 1: read the raw churn data and write the train/test split.

Session 5 (DVC Pipeline) file: the first stage of the pipeline, `preprocess`. It only reads
the raw data and splits it into a training part (train) and a test part (test). In Session 1
this split was inside `train.py`; now it is separate so DVC can cache and run every stage
on its own.

How to run:

    make train                          # runs the whole pipeline with `dvc repro`
    uv run python -m churn.preprocess   # only this stage, without DVC

Inputs: `params.yaml` (keys `data.raw_path`, `data.test_size`, `data.seed`) and the file
`data/raw/churn.csv` (versioned with DVC in Session 4).
Outputs: `data/processed/train.csv` and `data/processed/test.csv` (DVC caches them).

The next stage (`train.py`) reads only train.csv and `evaluate.py` reads only test.csv.
The `split` function is also used in the Session 5 tests.
The explanation in Persian is in CODE.md.
"""

import argparse
import pathlib

import pandas as pd
import yaml
from sklearn.model_selection import train_test_split

# Name of the target column; the train and evaluate stages import this constant from here.
TARGET = "churn"
# Output folder of this stage. The same folder name is in `dvc.yaml` (outs of preprocess).
OUT_DIR = pathlib.Path("data/processed")


def split(df: pd.DataFrame, test_size: float, seed: int) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Split the table into (train, test) with a fixed seed and stratification.

    A random but reproducible split. Because it is separate from `main`, tests can call it
    directly without reading or writing any file.

    Args:
        df: the whole data table (including the target column).
        test_size: share of the test data, e.g. 0.2 means 20% (from params.yaml).
        seed: fixed random number so every run gives the same split (from params.yaml).

    Returns:
        The pair `(train, test)` of two DataFrames. The index of the original rows is kept.
    """
    # stratify=df[TARGET]: the ratio of customers who left/stayed is the same in train and test.
    # random_state=seed: reproducible split; without it every run writes different files and
    # DVC thinks the data changed.
    return train_test_split(df, test_size=test_size, random_state=seed, stratify=df[TARGET])


def main(config: str) -> None:
    """Read raw data, split it and write the two CSV files into `data/processed/`.

    Args:
        config: path of the YAML settings file (default `params.yaml`).
    """
    # yaml.safe_load turns the YAML file into a dict; p["data"]["seed"] is the key seed
    # inside the data section.
    p = yaml.safe_load(open(config))
    df = pd.read_csv(p["data"]["raw_path"])
    train, test = split(df, p["data"]["test_size"], p["data"]["seed"])
    # parents=True: also create the parent folder if missing; exist_ok=True: no error if it exists.
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    # index=False: do not write the row-number column, so no extra column reaches the model.
    train.to_csv(OUT_DIR / "train.csv", index=False)
    test.to_csv(OUT_DIR / "test.csv", index=False)
    print(f"preprocess: {len(train)} train rows, {len(test)} test rows")


# Runs only when executed directly (`python -m churn.preprocess`), not when imported.
if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default="params.yaml")
    main(ap.parse_args().config)

"""Stage 2: fit logistic regression on the training split.

Session 5 (DVC Pipeline) file: the second stage of the pipeline, `train`. It trains the
logistic regression model only on `data/processed/train.csv` and saves it to
`models/model.joblib`. The `build_model` function is the same as in Session 1 (unchanged);
only reading the data and splitting it moved to the `preprocess` stage.

How to run:

    make train                          # the whole pipeline with dvc repro
    uv run python -m churn.train        # only this stage

Inputs: `data/processed/train.csv` (output of preprocess) and the `train` section of
`params.yaml` (values `C` and `max_iter`).
Output: `models/model.joblib`.
Next stage: `churn/evaluate.py` tests this model on test.csv. In Sessions 7 and 8 the same
`build_model` is also seen in model registration and the FastAPI service.
The explanation in Persian is in CODE.md.
"""

import argparse
import pathlib

import joblib
import pandas as pd
import yaml
from sklearn.compose import ColumnTransformer
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler

# Import from preprocess so the target name and the output folder are defined in one place.
from churn.preprocess import OUT_DIR, TARGET


def build_model(X: pd.DataFrame, C: float, max_iter: int) -> Pipeline:
    """Build (but do not fit) the preprocessing + logistic regression Pipeline.

    The model is a two-step Pipeline. Step one standardizes the numeric columns and one-hot
    encodes the text columns; step two is the classifier. Because the preprocessing lives
    inside the model, at prediction time (Session 8) the same transformations are applied
    to the input data automatically.

    Args:
        X: feature table (without the target); needed only to detect the column types.
        C: inverse regularization strength (smaller = more careful model); from params.yaml.
        max_iter: max optimizer iterations; from params.yaml.

    Returns:
        An unfitted `Pipeline`.
    """
    # Numeric columns come from the dtype; all the others (strings) count as categorical.
    num = X.select_dtypes("number").columns.tolist()
    cat = [c for c in X.columns if c not in num]
    # ColumnTransformer: a separate transformation per column group (name, transformer, columns).
    # StandardScaler puts numbers on one scale; OneHotEncoder turns categories into 0/1 columns.
    # handle_unknown="ignore": a category not seen in training does not raise an error (all zeros).
    pre = ColumnTransformer(
        [
            ("num", StandardScaler(), num),
            ("cat", OneHotEncoder(handle_unknown="ignore"), cat),
        ]
    )
    return Pipeline([("pre", pre), ("clf", LogisticRegression(C=C, max_iter=max_iter))])


def main(config: str) -> None:
    """Fit the model on `train.csv` and save it to `models/model.joblib`.

    Args:
        config: path of the YAML settings file (default `params.yaml`).
    """
    p = yaml.safe_load(open(config))
    df = pd.read_csv(OUT_DIR / "train.csv")
    # X = all columns except the target; y = the target column.
    X, y = df.drop(columns=[TARGET]), df[TARGET]
    # **p["train"] unpacks the dict {"C": ..., "max_iter": ...} into keyword arguments.
    # The same section is listed as params of the train stage in dvc.yaml; changing C reruns
    # only this stage and the next one.
    model = build_model(X, **p["train"]).fit(X, y)
    pathlib.Path("models").mkdir(exist_ok=True)
    joblib.dump(model, "models/model.joblib")
    print(f"train: fitted on {len(df)} rows with {p['train']}")


# Runs only when executed directly (`python -m churn.train`).
if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default="params.yaml")
    main(ap.parse_args().config)

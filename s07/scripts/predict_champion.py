"""Load models:/churn@champion from the Registry and score five test rows.

Session 7 script to try the Registry: it proves that a model registered with the alias
`@champion` can be loaded by name only (without knowing the run id or version number) and
used to predict on real data.

Run (from the project root, after `make register` and `make promote`):

    make predict        (= `uv run python scripts/predict_champion.py`)

Input: the MLflow server with the `@champion` model in the Registry, and
`data/processed/test.csv`, which the DVC preprocess stage creates. Output: printed text
only (model version, load time, signature column names and the churn probability of
5 rows). No file is created.

Connection to other sessions: in Session 8 the API service does the same job, except that
it loads the model once when the server starts and then answers every request.
"""

import time

import mlflow
import pandas as pd

from churn.preprocess import OUT_DIR, TARGET
from churn.registry import CHAMPION, MODEL_NAME, check_download_setting, connect

# Stop early with a clear message if the env variable that prevents the download hang is missing.
check_download_setting()
client = connect()
# Ask the Registry which version @champion points to (only to print it; load_model below
# resolves the alias again by itself).
mv = client.get_model_version_by_alias(MODEL_NAME, CHAMPION)
uri = f"models:/{MODEL_NAME}@{CHAMPION}"  # e.g. models:/churn@champion
start = time.time()
# Downloads the model files from S3 (through the MLflow server) and rebuilds the sklearn
# Pipeline, including the preprocessing, so we can pass raw columns directly.
model = mlflow.sklearn.load_model(uri)
print(f"loaded {uri} (version {mv.version}, run {mv.run_id[:8]}) in {time.time() - start:.1f} s")

# The signature is the model's input contract: column names and types it was trained with.
info = mlflow.models.get_model_info(uri)
print("signature inputs:", [c.name for c in info.signature.inputs])

# Read the test split, remove the label column (the model must not see the answer) and
# keep five rows only.
X = pd.read_csv(OUT_DIR / "test.csv").drop(columns=[TARGET]).head(5)
# predict_proba returns [P(stay), P(churn)] per row; [:, 1] keeps the churn column.
print("churn probability:", model.predict_proba(X)[:, 1].round(4).tolist())

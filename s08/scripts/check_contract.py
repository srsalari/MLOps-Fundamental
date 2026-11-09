"""Compare the API input contract (pydantic Customer) with the signature of @champion.

Added in Session 8. It is an "inspection": are the fields of the `Customer` class in
`churn/api.py` (what the API accepts from the user) exactly the same as the columns the
@champion model saw during training (its signature)? If someone adds a new feature to
the model but forgets to change the API, this script fails before deployment.

Run (from the project root, with the MLflow server running):

    make contract       (= `uv run python scripts/check_contract.py`)

Input: the signature of the `@champion` model from MLflow. Output: the list of columns
and their types on the screen, and at the end either `contract OK` or a `MISMATCH` list
with exit code 1. No file is written. The comparison logic is the function
`contract_mismatches` in `churn/api.py`, and its test is in `tests/test_api.py`.
"""

import mlflow

from churn.api import MODEL_URI, contract_mismatches
from churn.registry import connect

# connect() sets the tracking URI as a side effect; we do not need the client it returns.
connect()
# Only the model's metadata (signature) is read here: the model files are NOT downloaded.
signature = mlflow.models.get_model_info(MODEL_URI).signature
# to_dict() gives a list like [{"name": "tenure_months", "type": "double", ...}, ...]
inputs = signature.inputs.to_dict()
for col in inputs:
    print(f"  {col['name']:16} {col['type']}")  # :16 = pad the name to 16 characters (a table)
problems = contract_mismatches(inputs)  # empty list = the API and the model agree
for p in problems:
    print(f"  MISMATCH {p}")
if problems:
    # SystemExit with a string: prints it to stderr and exits with code 1 (fails CI / make)
    raise SystemExit(f"contract does NOT match {MODEL_URI}")
print(f"contract OK: Customer matches the signature of {MODEL_URI}")

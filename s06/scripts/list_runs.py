"""Print the runs of the 'churn' experiment as a small table (newest first).

Session 6 (MLflow Tracking) file, added to the `scripts/` folder. Without opening a browser,
it shows the runs of the experiment named `churn` in the terminal as a small table: run name,
value of C, threshold, roc_auc and f1, with the newest run on top.

How to run (the MLflow server must be running):

    make runs
    # same as: uv run python scripts/list_runs.py

Input: the runs recorded in MLflow (address from `MLFLOW_TRACKING_URI`; default
`http://localhost:5050`). Output: only printed on screen; nothing is written.
It uses functions from `churn.evaluate`, so the same server health check is done here too.
The explanation in Persian is in CODE.md.
"""

import mlflow

from churn.evaluate import EXPERIMENT, check_server, tracking_uri

# Get the server address and, if it is off, stop with a clear message (SystemExit).
uri = tracking_uri()
check_server(uri)
mlflow.set_tracking_uri(uri)
# search_runs returns a DataFrame (a pandas table) where every row is one run.
# The columns have long names: params.* parameters, metrics.* numbers, tags.* labels.
# order_by sorts on the server side: "start_time DESC" means newest first.
runs = mlflow.search_runs(experiment_names=[EXPERIMENT], order_by=["start_time DESC"])
# Map "column name in MLflow -> short name for display".
names = {
    "run_id": "run_id",
    "tags.mlflow.runName": "name",
    "params.train.C": "C",
    "params.eval.threshold": "threshold",
    "metrics.roc_auc": "roc_auc",
    "metrics.f1": "f1",
}
if runs.empty:
    # There is no run yet (the experiment does not exist or is empty): instead of a KeyError
    # we print a clear message and finish.
    print(f"no runs in experiment '{EXPERIMENT}' yet: run the pipeline first (make train)")
else:
    # list(names) gives the dict keys: keep only these columns and shorten their names.
    # reindex instead of []: if a column is in no run yet (for example a run that failed
    # before logging its parameters), that column shows as empty (NaN) and the program does
    # not break.
    table = runs.reindex(columns=list(names)).rename(columns=names)
    # The run id is long (32 characters); the first 8 are enough for display.
    table["run_id"] = table["run_id"].str[:8]
    # index=False: do not print the row-number column.
    print(table.to_string(index=False))

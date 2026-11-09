"""Model Registry: register a run's model as @challenger and promote it to @champion
only if it passes the evaluation gate (rules in params.yaml, section gate).

Added in Session 7. It does "register and promote a model".

Main idea: in Session 6 every training created one MLflow run. Now we must decide which
model is the "official" one used in production. We use the Model Registry and two
aliases (an alias is a movable label on one model version):

1) `@challenger` = a newly registered model that has not been checked yet.
2) `@champion` = the model that is officially in use.

Flow: `register` stores the model of one run as a new version of `churn` and puts
`@challenger` on it. Then `promote` checks the challenger against the rules in the
`gate` section of params.yaml (the evaluation gate). Only if it passes, `@champion` is
moved to that version. At the end `show` prints a table of all versions.

Commands (from the project root):

    make register RUN=<first 8 chars of the run id>   (= python -m churn.registry register)
    make promote                                      (= python -m churn.registry promote)
    make models                                       (= python -m churn.registry show)

Inputs: the MLflow server (address from `tracking_uri()` in `churn/evaluate.py`) and
params.yaml (section `gate`). Outputs: model versions, tags and aliases in the Registry
(inside the SQLite database of the MLflow server). The model files stay in `s3://mlflow/`
(SeaweedFS).

Connection to other sessions: this file uses `churn/evaluate.py` (Session 6). In Session 8
the API (`churn/api.py`) reuses `connect` and `check_download_setting` and loads the
`@champion` model from this same Registry.
"""

import argparse
import os

import mlflow
import yaml
from mlflow import MlflowClient
from mlflow.exceptions import MlflowException

from churn.evaluate import EXPERIMENT, check_server, tracking_uri

# Name of the registered model in the Registry (one name, many versions: 1, 2, 3...).
MODEL_NAME = "churn"
# Alias names are plain strings; the code never hard-codes a version number.
CHALLENGER = "challenger"
CHAMPION = "champion"


def connect() -> MlflowClient:
    """Return an MlflowClient connected to the tracking/registry server.

    It first checks that the MLflow server is really up (if not, it exits with a clear
    message), then sets the address for all `mlflow.*` functions and finally returns an
    `MlflowClient`. `MlflowClient` is the object that talks to the Registry (versions,
    aliases, tags).
    """
    uri = tracking_uri()
    check_server(uri)  # fails early with a clear message if the server is down
    # Global setting: after this, mlflow.register_model / load_model use this server.
    mlflow.set_tracking_uri(uri)
    return MlflowClient()


def check_download_setting() -> None:
    """Without this variable load_model hangs on the laptop (presigned URL to http://seaweedfs).

    Why: when `mlflow.sklearn.load_model` downloads the model files from S3, the MLflow
    server hands out a presigned URL that points to `http://seaweedfs...`. That address
    only works inside the Docker network, so from the laptop the download hangs forever
    without any error. With the value `false`, MLflow downloads the files through the
    MLflow server itself (a proxy) and the problem is gone.

    We call this function before every load_model, so a student gets a clear message
    instead of a hang. The variable lives in the `.env` file: `set -a; source .env; set +a`.

    Raises:
        SystemExit: if the variable is not set to "false".
    """
    # .lower() so "False", "FALSE" and "false" are all accepted; missing -> "" -> error
    if os.environ.get("MLFLOW_ENABLE_PROXY_MULTIPART_DOWNLOAD", "").lower() != "false":
        # SystemExit (not Exception): in a script it stops the program and prints the message
        # without a long traceback, which is friendlier for a student.
        raise SystemExit(
            "MLFLOW_ENABLE_PROXY_MULTIPART_DOWNLOAD=false is not set: load_model would hang.\n"
            "Fix: set -a; source .env; set +a"
        )


def find_run(client: MlflowClient, prefix: str):
    """The run of experiment 'churn' whose id starts with prefix (8 chars from `make runs`).

    Why a prefix? The full run id has 32 characters and is hard to type. `make runs`
    prints only the first 8, so we accept that. If no run, or more than one run, starts
    with it, the program stops with a clear message.

    Args:
        client: connected MlflowClient.
        prefix: first characters of the run id.

    Returns:
        The single matching `mlflow.entities.Run`.

    Raises:
        SystemExit: experiment missing, or zero / more than one run matches.
    """
    exp = client.get_experiment_by_name(EXPERIMENT)
    if exp is None:
        raise SystemExit(f"experiment '{EXPERIMENT}' not found: run the pipeline first")
    # List comprehension with a filter: keep only runs whose id starts with the prefix.
    # MLflow cannot search by "id starts with", so we fetch (up to 1000) and filter in Python.
    runs = [
        r
        for r in client.search_runs([exp.experiment_id], max_results=1000)
        if r.info.run_id.startswith(prefix)
    ]
    if len(runs) != 1:  # 0 = typo, 2+ = prefix too short: both are unsafe to guess
        raise SystemExit(f"expected 1 run starting with '{prefix}', found {len(runs)}")
    return runs[0]


def get_alias(client: MlflowClient, alias: str):
    """Return the model version that `alias` points to, or None if the alias does not exist.

    When the alias does not exist yet (for example the first time, when there is no
    @champion), MLflow raises `MlflowException`. We turn that into `None`, so the caller
    can say "no champion yet" with a simple `if`.
    """
    try:
        return client.get_model_version_by_alias(MODEL_NAME, alias)
    except MlflowException:
        return None


def release_note(run) -> str:
    """Build the human-readable description stored on the model version.

    This text appears in the MLflow UI, so anyone can later see which hyperparameters,
    metrics, data (md5) and git commit produced this version. It is full traceability:
    model -> run -> data -> code.

    Args:
        run: an `mlflow.entities.Run` (the training run).

    Returns:
        One line of text.
    """
    # Tuple unpacking: three dicts in one line (metrics are floats, params/tags are strings).
    m, p, t = run.data.metrics, run.data.params, run.data.tags
    # [:7] = short git hash; "unknown" is the fallback if MLflow could not read git
    commit = t.get("mlflow.source.git.commit", "unknown")[:7]
    return (
        f"LogisticRegression C={p.get('train.C')} threshold={p.get('eval.threshold')}. "
        f"roc_auc={m['roc_auc']} f1={m['f1']}. "
        f"data md5 {t.get('data_md5', 'unknown')[:8]}, git commit {commit}, "
        f"run {run.info.run_id[:8]}."
    )


def register(client: MlflowClient, prefix: str):
    """Register the model of one run as a new version of 'churn' and point @challenger at it.

    Steps: 1) find the run. 2) register the logged model of that run as a new version of
    `churn` (versions are numbered 1, 2, 3... automatically). 3) write the description and
    the tags on the version. 4) move the alias `@challenger` to this version. Note that
    this function never changes `@champion`; promotion is only done by `promote`, and only
    after the gate.

    Args:
        client: connected MlflowClient.
        prefix: run id prefix (see `find_run`).

    Returns:
        The new `ModelVersion`.
    """
    run = find_run(client, prefix)
    # MLflow 3 logs each trained model as a "logged model" with its own id; the run keeps
    # a list of its outputs, and the first one is our sklearn pipeline.
    model_id = run.outputs.model_outputs[0].model_id
    # Creates version N of 'churn' from that logged model (no re-upload of the files).
    mv = mlflow.register_model(f"models:/{model_id}", MODEL_NAME)
    client.update_model_version(MODEL_NAME, mv.version, description=release_note(run))
    # Tags are searchable key/value strings on the version. We copy the numbers here so
    # that `show` and `promote` can print them without opening the run.
    for key in ("roc_auc", "f1"):
        client.set_model_version_tag(MODEL_NAME, mv.version, key, run.data.metrics[key])
    client.set_model_version_tag(MODEL_NAME, mv.version, "train.C", run.data.params["train.C"])
    client.set_model_version_tag(MODEL_NAME, mv.version, "data_md5", run.data.tags["data_md5"])
    # If @challenger already pointed to an older version, it simply moves to this one.
    client.set_registered_model_alias(MODEL_NAME, CHALLENGER, mv.version)
    print(f"registered {MODEL_NAME} version {mv.version} from run {run.info.run_id[:8]}", end=" ")
    print(f"-> @{CHALLENGER}")  # the first print has end=" " so both prints form one line
    return mv


def gate(challenger: dict, champion: dict | None, rules: dict) -> list[str]:
    """Release gate. Returns the list of failed rules (empty list = passed).

    This is the "quality gate". It has nothing to do with MLflow: it only compares a few
    numbers with the rules. That is why it is easy to test without any server.

    It has three rules (the values are in the `gate` section of `params.yaml`):
    1) `min_roc_auc`: an absolute floor for roc_auc.
    2) `min_f1`: an absolute floor for f1.
    3) `max_roc_auc_drop`: if a champion exists, the roc_auc of the new model must not be
       lower than the champion by more than this value (a tiny drop is fine, a big one
       is not).

    Note: f1 can get better while roc_auc gets worse. The gate checks every rule
    separately and returns ALL failures, not only the first one, so you can see
    everything that is wrong.

    Args:
        challenger: metrics of the new model, e.g. {"roc_auc": 0.74, "f1": 0.70}.
        champion: metrics of the current champion, or None if there is none yet.
        rules: dict with min_roc_auc, min_f1, max_roc_auc_drop.

    Returns:
        List of human-readable failure messages; an empty list means the gate passed.
    """
    failed = []
    if challenger["roc_auc"] < rules["min_roc_auc"]:
        failed.append(f"roc_auc {challenger['roc_auc']} < min_roc_auc {rules['min_roc_auc']}")
    if challenger["f1"] < rules["min_f1"]:
        failed.append(f"f1 {challenger['f1']} < min_f1 {rules['min_f1']}")
    if champion is not None:  # the "no regression" rule only makes sense if a champion exists
        # round(..., 4): avoids float noise such as 0.7482999999 in the comparison
        floor = round(champion["roc_auc"] - rules["max_roc_auc_drop"], 4)
        if challenger["roc_auc"] < floor:
            failed.append(
                f"roc_auc {challenger['roc_auc']} < champion {champion['roc_auc']}"
                f" - max_roc_auc_drop {rules['max_roc_auc_drop']}"
            )
    return failed


def metrics_of(client: MlflowClient, mv) -> dict:
    """Return the metrics dict of the run that produced model version `mv`.

    We read the metrics from the run itself (not from the tags) because the run is the
    original source of truth.
    """
    return client.get_run(mv.run_id).data.metrics


def promote(client: MlflowClient, rules: dict) -> bool:
    """Move @champion to the @challenger version if it passes the gate.

    Steps: 1) read the challenger version (error if there is none). 2) if this version is
    already the champion, do nothing. 3) print the metrics of the challenger and of the
    current champion. 4) run `gate` and write the result as a tag (`gate=passed` or
    `failed`) on the version. 5) only if the gate passed, move the alias `@champion`.

    Args:
        client: connected MlflowClient.
        rules: the `gate` section of params.yaml.

    Returns:
        True if @champion now points to the challenger version, False if the gate failed.
        (main() turns False into exit code 1 so `make promote` shows an error.)

    Raises:
        SystemExit: if there is no @challenger yet.
    """
    chal = get_alias(client, CHALLENGER)
    if chal is None:
        raise SystemExit(f"no @{CHALLENGER} yet: make register RUN=<run id>")
    champ = get_alias(client, CHAMPION)  # None the first time
    # str(...) on both sides: versions can be int or str depending on the MLflow call
    if champ is not None and str(champ.version) == str(chal.version):
        print(f"version {chal.version} is already @{CHAMPION}")
        return True
    c_metrics = metrics_of(client, chal)
    old = metrics_of(client, champ) if champ else None  # conditional expression
    print(f"challenger: version {chal.version} roc_auc={c_metrics['roc_auc']} f1={c_metrics['f1']}")
    if champ:
        print(f"champion:   version {champ.version} roc_auc={old['roc_auc']} f1={old['f1']}")
    else:
        print("champion:   none yet")
    failed = gate(c_metrics, old, rules)
    # The verdict is stored on the version, so it is visible later in `make models` and the UI
    client.set_model_version_tag(MODEL_NAME, chal.version, "gate", "failed" if failed else "passed")
    if failed:
        for reason in failed:
            print(f"  FAIL {reason}")
        # a failed gate does NOT touch @champion: production keeps the old model
        print(f"gate FAILED: @{CHAMPION} stays on version {champ.version if champ else '-'}")
        return False
    # The actual promotion is just moving an alias: no files are copied.
    client.set_registered_model_alias(MODEL_NAME, CHAMPION, chal.version)
    print(f"gate passed: @{CHAMPION} -> version {chal.version}")
    return True


def show(client: MlflowClient) -> None:
    """Print a table of all versions of 'churn' with their metrics, gate result and aliases.

    This is the output of `make models`. Each row is one version, and the last column
    shows which aliases point to that version (for example `@champion`).
    """
    versions = client.search_model_versions(f"name='{MODEL_NAME}'")
    if not versions:
        print(f"no versions of '{MODEL_NAME}' yet")
        return
    # dict like {"champion": "2", "challenger": "3"}: alias name -> version number
    aliases = client.get_registered_model(MODEL_NAME).aliases
    # Format spec: >7 right-align in 7 chars, 8 = pad to 8 chars (left-aligned for strings)
    print(f"{'version':>7} {'run':8} {'C':>6} {'roc_auc':>7} {'f1':>6} {'gate':6}  aliases")
    # key=int(...): sort numerically (so version 10 comes after 9, not after 1)
    for mv in sorted(versions, key=lambda v: int(v.version)):
        # generator inside join: "@champion,@x" for every alias that points to this version
        names = ",".join(f"@{a}" for a, v in aliases.items() if str(v) == str(mv.version))
        t = mv.tags
        print(
            f"{mv.version:>7} {mv.run_id[:8]} {t.get('train.C', ''):>6} {t.get('roc_auc', ''):>7}"
            f" {t.get('f1', ''):>6} {t.get('gate', '-'):6}  {names}"
        )


def main() -> None:
    """Command-line entry point: parse the sub-command, connect, run it, then show the table.

    It uses `argparse` with sub-commands, like `git commit` and `git push`, which have
    their own options: `register --run ...`, `promote [--config ...]`, `show`.
    """
    ap = argparse.ArgumentParser()
    # dest="cmd": the chosen sub-command name is saved in args.cmd; required=True: no default
    sub = ap.add_subparsers(dest="cmd", required=True)
    reg = sub.add_parser("register")
    reg.add_argument("--run", required=True, help="run id or its first 8 characters")
    pro = sub.add_parser("promote")
    pro.add_argument("--config", default="params.yaml")
    sub.add_parser("show")
    args = ap.parse_args()

    client = connect()
    if args.cmd == "register":
        register(client, args.run)
    elif args.cmd == "promote":
        # safe_load: parse YAML without running arbitrary code; ["gate"] = the rules section
        rules = yaml.safe_load(open(args.config))["gate"]
        if not promote(client, rules):
            raise SystemExit(1)  # exit code 1 = failure, so CI / make can detect a failed gate
    show(client)  # always print the table at the end (also for the `show` sub-command)


if __name__ == "__main__":  # only when run as a script, not when imported by tests or api.py
    main()

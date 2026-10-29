"""Unit tests for the pipeline functions: split, build_model and score.

Session 5 file, copied into the project's `tests/` folder. It checks the logic of the three
pipeline stages without running DVC and without reading or writing files (only small
synthetic data in memory). Run: `make test` or `uv run pytest -q`. The tests are fast
because they use only a few hundred rows.
`make_dataset` can be imported thanks to `pythonpath = ["scripts"]` in pyproject.toml.
The explanation in Persian is in CODE.md.
"""

from churn.evaluate import score
from churn.preprocess import split
from churn.train import build_model
from make_dataset import make


def test_split_sizes_and_no_overlap():
    """The split has the requested sizes and no row is in both train and test.

    If a row is in both train and test (data leakage), the model is tested on something it
    has already seen, and the evaluation number is optimistic and false.
    `isdisjoint` means the two sets have no common member.
    """
    df = make(rows=500, seed=1)
    train, test = split(df, test_size=0.2, seed=42)
    assert len(train) == 400
    assert len(test) == 100
    # split keeps the index of the original rows, so comparing indexes finds any overlap.
    assert set(train.index).isdisjoint(test.index)


def test_split_is_reproducible():
    """Calling `split` twice with the same seed gives the same rows.

    If the split is not reproducible, every `dvc repro` writes different files and results
    cannot be compared. Here we compare only the indexes; `_` means we do not need the
    test part.
    """
    df = make(rows=500, seed=1)
    a, _ = split(df, 0.2, 42)
    b, _ = split(df, 0.2, 42)
    assert a.index.tolist() == b.index.tolist()


def test_evaluate_returns_metric_keys():
    """`score` returns exactly the keys roc_auc and f1, with roc_auc in [0, 1].

    This test runs the whole small train-and-evaluate path from start to end. If someone
    renames a metric key, `dvc metrics show` and MLflow (Session 6) break; this test shows
    it early.
    """
    df = make(rows=600, seed=1)
    train, test = split(df, 0.25, 42)
    # build_model uses X only to detect the column types; then fit trains with the real X and y.
    model = build_model(train.drop(columns=["churn"]), C=1.0, max_iter=200).fit(
        train.drop(columns=["churn"]), train["churn"]
    )
    metrics = score(model, test, threshold=0.5)
    assert set(metrics) == {"roc_auc", "f1"}
    # Python chained comparison: both 0 <= x and x <= 1 must hold.
    assert 0 <= metrics["roc_auc"] <= 1

from drift_report import summarize


def snapshot(*items):
    metrics = [
        {
            "config": {
                "type": "evidently:metric_v2:ValueDrift",
                "column": c,
                "method": m,
                "threshold": t,
            },
            "value": v,
        }
        for c, m, t, v in items
    ]
    # the overall counter is not a column: summarize must skip it
    metrics.append({"config": {"type": "evidently:metric_v2:DriftedColumnsCount"}, "value": {}})
    return {"metrics": metrics}


def test_distance_at_or_above_threshold_is_drift():
    rows = summarize(
        snapshot(
            ("a", "Wasserstein distance (normed)", 0.1, 0.5),
            ("b", "Jensen-Shannon distance", 0.1, 0.01),
        )
    )
    assert [(r["column"], r["drift"]) for r in rows] == [("a", True), ("b", False)]


def test_p_value_below_threshold_is_drift():
    rows = summarize(snapshot(("a", "K-S p_value", 0.05, 0.001), ("b", "K-S p_value", 0.05, 0.4)))
    assert [r["drift"] for r in rows] == [True, False]

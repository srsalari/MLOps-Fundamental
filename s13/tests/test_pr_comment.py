from pr_comment import MARKER, build_body, find_comment


def test_body_starts_with_marker_and_keeps_the_table():
    body = build_body("| Path | roc_auc |\n|---|---|\n| metrics.json | 0.75 |")
    assert body.startswith(MARKER)
    assert "| metrics.json | 0.75 |" in body


def test_empty_table_gets_a_message():
    assert "no metrics" in build_body("  \n").lower()


def test_find_comment_picks_the_one_with_the_marker():
    comments = [{"id": 1, "body": "looks good"}, {"id": 2, "body": MARKER + "\nold"}]
    assert find_comment(comments)["id"] == 2
    assert find_comment([{"id": 1, "body": "hi"}]) is None

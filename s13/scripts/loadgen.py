"""Send fake traffic to the churn API so the Grafana dashboard has something to show.

Usage:
    python scripts/loadgen.py --url http://localhost:8003 --rps 5 --seconds 60

Most requests are valid customers (status 200). With --bad-rate a share of the requests
is wrong on purpose (a negative tenure) and the API answers 422: that is the "4xx" line
on the dashboard. If the API has no model (make api-break) every valid request gets 503:
that is the "5xx" line. Code 0 in the summary means "no answer at all" (the API was
restarting).
"""

import argparse
import http.client
import json
import random
import time
import urllib.error
import urllib.request
from collections import Counter


def customer(rng: random.Random, bad: bool = False) -> dict:
    """One random customer. bad=True breaks the input contract (tenure_months < 0)."""
    return {
        "tenure_months": -5 if bad else rng.randint(1, 72),
        "monthly_charges": round(rng.uniform(20, 120), 2),
        "contract": rng.choice(["month-to-month", "one-year", "two-year"]),
        "internet_service": rng.choice(["dsl", "fiber", "none"]),
        "payment_method": rng.choice(["card", "bank_transfer", "cash"]),
        "support_calls": rng.randint(0, 8),
    }


def send(url: str, body: dict) -> int:
    """POST one customer to /predict and return the HTTP status code."""
    req = urllib.request.Request(
        f"{url}/predict",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return resp.status
    except urllib.error.HTTPError as e:  # 4xx and 5xx arrive here
        return e.code
    except (OSError, http.client.HTTPException):  # no answer at all (API restarting): code 0
        return 0


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://localhost:8003")
    ap.add_argument("--rps", type=float, default=5, help="requests per second")
    ap.add_argument("--seconds", type=float, default=60)
    ap.add_argument("--bad-rate", type=float, default=0.0, help="share of wrong requests, 0 to 1")
    ap.add_argument("--seed", type=int, default=1)
    a = ap.parse_args()
    rng = random.Random(a.seed)
    codes: Counter = Counter()
    end = time.monotonic() + a.seconds
    while time.monotonic() < end:
        started = time.monotonic()
        codes[send(a.url, customer(rng, bad=rng.random() < a.bad_rate))] += 1
        time.sleep(max(0.0, 1 / a.rps - (time.monotonic() - started)))
    print("status codes:", dict(sorted(codes.items())))


if __name__ == "__main__":
    main()

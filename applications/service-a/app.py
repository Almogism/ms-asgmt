import os
import time
import logging
import threading
from collections import deque
from datetime import datetime

import requests
from flask import Flask, jsonify

# ── Logging ─────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
)
logger = logging.getLogger(__name__)

# ── Config ───────────────────────────────────────────────────────────────────
FETCH_INTERVAL_SEC   = int(os.getenv("FETCH_INTERVAL_SEC",  "60"))
AVERAGE_INTERVAL_SEC = int(os.getenv("AVERAGE_INTERVAL_SEC", "600"))   # 10 min
BTC_API_URL          = os.getenv(
    "BTC_API_URL",
    "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=usd",
)

# ── State ─────────────────────────────────────────────────────────────────────
# Keep the last 10 readings (one per minute → 10-minute window)
price_window: deque[float] = deque(maxlen=AVERAGE_INTERVAL_SEC // FETCH_INTERVAL_SEC)
latest_price: float | None = None
last_fetch_ok: bool        = False

# ── Flask app (health endpoints) ──────────────────────────────────────────────
app = Flask(__name__)


@app.route("/healthz/live")
def liveness():
    """Kubernetes liveness probe – always alive once the process is running."""
    return jsonify(status="ok"), 200


@app.route("/healthz/ready")
def readiness():
    """
    Kubernetes readiness probe – only ready after the first successful fetch.
    This prevents the pod from receiving traffic before it has real data.
    """
    if last_fetch_ok:
        return jsonify(status="ready", latest_price_usd=latest_price), 200
    return jsonify(status="not ready", reason="waiting for first BTC fetch"), 503


@app.route("/price")
def price():
    if latest_price is None:
        return jsonify(error="no data yet"), 503
    avg = sum(price_window) / len(price_window) if price_window else None
    return jsonify(
        latest_price_usd=latest_price,
        average_last_window_usd=avg,
        window_samples=len(price_window),
    ), 200


# ── Bitcoin fetcher ───────────────────────────────────────────────────────────

def fetch_bitcoin_price() -> float | None:
    try:
        resp = requests.get(BTC_API_URL, timeout=10)
        resp.raise_for_status()
        data = resp.json()
        return float(data["bitcoin"]["usd"])
    except Exception as exc:
        logger.error("Failed to fetch BTC price: %s", exc)
        return None


def price_loop() -> None:
    global latest_price, last_fetch_ok

    fetch_count = 0

    while True:
        price = fetch_bitcoin_price()

        if price is not None:
            latest_price  = price
            last_fetch_ok = True
            price_window.append(price)
            fetch_count  += 1

            logger.info(
                "BTC price: $%.2f  |  sample #%d",
                price, fetch_count,
            )

            # Print rolling average every 10 samples (= 10 minutes)
            if fetch_count % (AVERAGE_INTERVAL_SEC // FETCH_INTERVAL_SEC) == 0:
                avg = sum(price_window) / len(price_window)
                logger.info(
                    "── 10-min average BTC price: $%.2f  (over %d samples) ──",
                    avg, len(price_window),
                )
        else:
            last_fetch_ok = False
            logger.warning("Skipping this cycle – price unavailable.")

        time.sleep(FETCH_INTERVAL_SEC)


# ── Entry point ───────────────────────────────────────────────────────────────

def start_background_fetcher():
    fetcher = threading.Thread(target=price_loop, daemon=True, name="btc-fetcher")
    fetcher.start()
    logger.info(
        "Service A started — fetching BTC every %ds, averaging every %ds",
        FETCH_INTERVAL_SEC, AVERAGE_INTERVAL_SEC,
    )

start_background_fetcher()  # runs on import — works with gunicorn too

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
## Service A: Bitcoin Price Tracker & Rolling Average

A lightweight Python service that monitors Bitcoin prices in real-time, calculates a rolling average over a 10-minute window, and exposes health and data endpoints.

---

## Key Features
*   **Real-time Monitoring**: Fetches the current BTC/USD price every 60 seconds (configurable).
*   **Rolling Average**: Maintains a 10-minute price window using a `deque` to calculate the average price over the last 10 samples.
*   **Cloud-Native Ready**: Includes built-in Kubernetes liveness (`/healthz/live`) and readiness (`/healthz/ready`) probes.
*   **Threaded Architecture**: Runs the price fetcher in a background daemon thread to ensure the API remains responsive.

---

## API Endpoints
*   `GET /price`: Returns the latest BTC price, the current 10-minute average, and the number of samples in the window.
*   `GET /healthz/live`: Always returns `200 OK` to indicate the process is running.
*   `GET /healthz/ready`: Returns `200 OK` only after the first successful price fetch, ensuring the service doesn't serve traffic without data.

---

## Configuration
The application can be configured via environment variables:

| Variable | Default | Description |
| :--- | :--- | :--- |
| `FETCH_INTERVAL_SEC` | `60` | Frequency of price fetches in seconds |
| `AVERAGE_INTERVAL_SEC` | `600` | The window size for the rolling average |
| `BTC_API_URL` | Coingecko API | The source URL for BTC price data |

---

## Quick Start
1.  **Install dependencies**: `pip install -r requirements.txt`.
2.  **Run the app**: `python app.py`.
3.  **Access the data**: Navigate to `http://localhost:8080/price`.
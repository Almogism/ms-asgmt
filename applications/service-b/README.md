## Service B: Echo & Diagnostic API

A simple, lightweight Flask-based echo service designed for request inspection, connectivity testing, and Kubernetes deployment demonstrations.

---

## Key Features
* **Request Mirroring**: Captures and returns request metadata, including HTTP methods, paths, and headers.
* **Environment Aware**: Dynamically identifies itself using configurable service names and versions.
* **Cloud-Native Probes**: Includes dedicated health check endpoints for liveness and readiness monitoring.
* **Catch-All Routing**: Handles any incoming path to simplify debugging and traffic flow visualization.

---

## API Endpoints

| Endpoint | Method | Description |
| :--- | :--- | :--- |
| `/*` | ANY | The catch-all route; returns hostname, service info, and request headers. |
| `/healthz/live` | GET | Liveness probe; returns `200 OK` to indicate the process is alive. |
| `/healthz/ready` | GET | Readiness probe; returns `200 OK` to indicate the service is ready for traffic. |

---

## Configuration
The application behavior can be customized using environment variables:

* **`SERVICE_NAME`**: The name identifier for the service (Defaults to `service-b`).
* **`SERVICE_VERSION`**: The version string displayed in the response (Defaults to `1.0.0`).

---

## Quick Start

1.  **Install Requirements**:
    `pip install -r requirements.txt`

2.  **Run the Service**:
    `python app.py`

3.  **Test the Output**:
    `curl http://localhost:8080/debug-path`
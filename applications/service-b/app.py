import os
import socket
from flask import Flask, jsonify, request

app = Flask(__name__)

SERVICE_NAME = os.getenv("SERVICE_NAME", "service-b")
VERSION      = os.getenv("SERVICE_VERSION", "1.0.0")


@app.route("/healthz/live")
def liveness():
    return jsonify(status="ok"), 200


@app.route("/healthz/ready")
def readiness():
    return jsonify(status="ready"), 200


@app.route("/", defaults={"path": ""})
@app.route("/<path:path>")
def catch_all(path):
    return jsonify(
        service=SERVICE_NAME,
        version=VERSION,
        hostname=socket.gethostname(),
        method=request.method,
        path=f"/{path}",
        headers=dict(request.headers),
        message="Hello from Service B 👋",
    ), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)

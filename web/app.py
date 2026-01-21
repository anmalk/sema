from flask import Flask, render_template, jsonify, request
import requests, os

app = Flask(__name__)
API_BASE = os.getenv("API_BASE", "http://89.169.188.151:8000")

@app.route("/")
def index():
    return render_template("index.html")

@app.route("/api/projects", methods=["POST"])
def api_create_project():
    r = requests.post(f"{API_BASE}/projects", json={"name": request.json.get("name","New")}, timeout=60)
    return jsonify(r.json()), r.status_code

@app.route("/api/runs", methods=["POST"])
def api_create_run():
    project_id = int(request.json["project_id"])
    payload = {
        "group_id": request.json["group_id"],  
        "count": int(request.json.get("count", 50))
    }
    r = requests.post(f"{API_BASE}/projects/{project_id}/runs", json=payload, timeout=60)
    return jsonify(r.json()), r.status_code

@app.route("/api/runs/<int:run_id>")
def api_get_run(run_id: int):
    r = requests.get(f"{API_BASE}/runs/{run_id}", timeout=60)
    return jsonify(r.json()), r.status_code

@app.route("/api/runs/<int:run_id>/report")
def api_get_report(run_id: int):
    r = requests.get(f"{API_BASE}/runs/{run_id}/report", timeout=60)
    return jsonify(r.json()), r.status_code

if __name__ == "__main__":
    app.run(host="127.0.0.1", port=3000, debug=True)
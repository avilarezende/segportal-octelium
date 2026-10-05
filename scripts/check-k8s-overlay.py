"""Build the real upstream overlay and enforce the private entry boundary."""

import subprocess
from pathlib import Path

import yaml

root = Path(__file__).resolve().parents[1]
rendered = subprocess.run(
    ["kubectl", "kustomize", str(root / "k8s/overlays/octelium")],
    check=True,
    capture_output=True,
    text=True,
).stdout
docs = [doc for doc in yaml.safe_load_all(rendered) if doc]
assert not any(doc["kind"] == "Ingress" for doc in docs), "Public Ingress remains"
assert any(doc["kind"] == "NetworkPolicy" for doc in docs), "NetworkPolicy is missing"
deployments = {doc["metadata"]["name"] for doc in docs if doc["kind"] == "Deployment"}
assert {"guacamole", "guacd", "proxy-egress", "web-browser"} <= deployments
print("Overlay OK: upstream workloads and NetworkPolicy present; no public Ingress")

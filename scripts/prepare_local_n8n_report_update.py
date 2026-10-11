"""Prepare a private n8n export for updating the three report formatters."""

import argparse
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FORMATTERS = {
    "02 - Intraday Report": "intraday.js",
    "03 - Daily Report": "daily.js",
    "04 - Critical Alert": "critical_alert.js",
}

parser = argparse.ArgumentParser()
parser.add_argument("source", type=Path, help="Private export from the existing n8n instance")
parser.add_argument("destination", type=Path, help="Private import file; keep outside Git")
args = parser.parse_args()

workflows = json.loads(args.source.read_text(encoding="utf-8"))
if not isinstance(workflows, list):
    raise SystemExit("Expected a list from n8n export:workflow --all")

selected = []
for workflow in workflows:
    name = workflow.get("name")
    if name not in FORMATTERS:
        continue
    if not workflow.get("active"):
        raise SystemExit(f"Expected active workflow: {name}")
    code_nodes = [node for node in workflow["nodes"] if node["type"] == "n8n-nodes-base.code"]
    if len(code_nodes) != 1:
        raise SystemExit(f"Expected one Code node in {name}")
    formatter = ROOT / "n8n" / "formatters" / FORMATTERS[name]
    code_nodes[0]["parameters"]["jsCode"] = formatter.read_text(encoding="utf-8")
    selected.append(workflow)

if {workflow["name"] for workflow in selected} != set(FORMATTERS):
    raise SystemExit("Private export is missing one or more report workflows")

args.destination.parent.mkdir(parents=True, exist_ok=True)
args.destination.write_text(json.dumps(selected, ensure_ascii=False), encoding="utf-8")
print("Prepared three report workflows. Review and import privately; then publish and restart n8n.")

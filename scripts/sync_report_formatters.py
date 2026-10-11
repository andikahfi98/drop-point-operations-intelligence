"""Copy standalone Telegram formatters into the public n8n workflow examples."""

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCES = {
    "02_intraday_report.json": "intraday.js",
    "03_daily_report.json": "daily.js",
    "04_critical_alert.json": "critical_alert.js",
}


for workflow_name, formatter_name in SOURCES.items():
    workflow_path = ROOT / "n8n" / "workflows" / workflow_name
    formatter_path = ROOT / "n8n" / "formatters" / formatter_name
    workflow = json.loads(workflow_path.read_text(encoding="utf-8"))
    code_nodes = [node for node in workflow["nodes"] if node["type"] == "n8n-nodes-base.code"]
    if len(code_nodes) != 1:
        raise SystemExit(f"Expected one Code node in {workflow_name}")
    code_nodes[0]["parameters"]["jsCode"] = formatter_path.read_text(encoding="utf-8")
    workflow_path.write_text(json.dumps(workflow, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Synced {formatter_name} -> {workflow_name}")

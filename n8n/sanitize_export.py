"""Create importable, credential-free workflow examples from an n8n export."""
import copy
import json
import re
import sys
from pathlib import Path

source = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("n8n/workflows.raw.json")
out_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("n8n/workflows")
out_dir.mkdir(parents=True, exist_ok=True)

for workflow in json.loads(source.read_text(encoding="utf-8")):
    nodes = copy.deepcopy(workflow["nodes"])
    for node in nodes:
        node.pop("credentials", None)
        params = node.get("parameters", {})
        for header in params.get("headerParameters", {}).get("parameters", []):
            if header.get("name", "").lower() == "x-internal-key":
                header["value"] = "REPLACE_WITH_INTERNAL_API_KEY"
        if node.get("type", "").endswith(".telegram") and "chatId" in params:
            params["chatId"] = "REPLACE_WITH_REGIONAL_CHAT_ID"
    public = {
        "name": workflow["name"],
        "nodes": nodes,
        "connections": workflow["connections"],
        "settings": workflow.get("settings", {}),
        "active": False,
    }
    number = re.match(r"^(\d+)", workflow["name"]).group(1)
    slug = re.sub(r"[^a-z0-9]+", "_", workflow["name"].split(" - ", 1)[1].lower()).strip("_")
    target = out_dir / f"{number}_{slug}.json"
    target.write_text(json.dumps(public, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(target)

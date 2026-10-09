"""Run integration checks against the host-exposed project database."""

import os
import subprocess
import sys
from pathlib import Path

from dotenv import dotenv_values


ROOT = Path(__file__).resolve().parents[1]
config = dotenv_values(ROOT / ".env")
password = config.get("POSTGRES_PASSWORD")
if not password:
    raise SystemExit("POSTGRES_PASSWORD is missing from the local .env file.")

env = os.environ.copy()
env.update(
    DB_HOST="localhost",
    DB_PORT="5433",
    DB_NAME="drop_point_ops",
    DB_USER="postgres",
    DB_PASSWORD=password,
    SIMULATION_API_KEY=config.get("SIMULATION_API_KEY") or "",
    PYTHONPATH=os.pathsep.join(filter(None, (str(ROOT), env.get("PYTHONPATH")))),
)

checks = [[sys.executable, "tests/test_auth_integration.py"]]
if "--browser" in sys.argv[1:]:
    checks.append([sys.executable, "frontend/tests/live_browser.py"])

for command in checks:
    result = subprocess.run(command, cwd=ROOT, env=env, check=False)
    if result.returncode:
        raise SystemExit(result.returncode)

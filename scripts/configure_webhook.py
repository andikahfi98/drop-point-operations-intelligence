"""Register or inspect the Telegram webhook without printing the bot token."""
import argparse
import os
from pathlib import Path

import httpx
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[1]
load_dotenv(ROOT / ".env", override=True)

parser = argparse.ArgumentParser()
parser.add_argument("--check", action="store_true", help="Inspect the registered webhook without changing it")
args = parser.parse_args()

token = os.getenv("TELEGRAM_BOT_TOKEN", "").strip()
base = os.getenv("N8N_WEBHOOK_URL", "").strip().rstrip("/")
if not token or not base.startswith("https://"):
    raise SystemExit("Set TELEGRAM_BOT_TOKEN and an HTTPS N8N_WEBHOOK_URL in .env first.")

expected = f"{base}/webhook/telegram-ops"
api = f"https://api.telegram.org/bot{token}"
with httpx.Client(timeout=30) as client:
    if not args.check:
        result = client.post(f"{api}/setWebhook", data={"url": expected, "drop_pending_updates": "false"}).json()
        if not result.get("ok"):
            raise SystemExit(f"Telegram rejected the webhook: {result.get('description', 'unknown error')}")
    result = client.get(f"{api}/getWebhookInfo").json()
    if not result.get("ok"):
        raise SystemExit("Could not read Telegram webhook status.")

info = result["result"]
print(f"Webhook URL matches .env: {info.get('url') == expected}")
print(f"Pending updates: {info.get('pending_update_count', 0)}")
print(f"Last error: {info.get('last_error_message') or 'none'}")

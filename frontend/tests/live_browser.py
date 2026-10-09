"""Temporary regional login for browser QA; account is always removed."""

import os
import secrets
import subprocess
import sys
from pathlib import Path

from dotenv import dotenv_values
from sqlalchemy import text

frontend = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(frontend.parent))
local_env = dotenv_values(frontend.parent / '.env')
os.environ["DB_HOST"] = "127.0.0.1"
os.environ["DB_PORT"] = "5433"
os.environ["DB_USER"] = "postgres"
os.environ["DB_NAME"] = "drop_point_ops"
os.environ["DB_PASSWORD"] = local_env.get("POSTGRES_PASSWORD") or local_env.get("DB_PASSWORD") or ""
from app.db.database import engine


user_id = f"TEST-WEB-{secrets.token_hex(4).upper()}"
dp_user_id = f"TEST-WEB-DP-{secrets.token_hex(4).upper()}"
email = f"{user_id.lower()}@demo.local"
dp_email = f"{dp_user_id.lower()}@demo.local"
password = secrets.token_urlsafe(22)
dp_password = secrets.token_urlsafe(22)
dp_new_password = secrets.token_urlsafe(24)
created = False

try:
    with engine.begin() as connection:
        points = connection.execute(text("""
            SELECT drop_point_id, region FROM core.dim_drop_point
            WHERE status = 'ACTIVE' ORDER BY drop_point_id
        """)).mappings().all()
        assert len(points) >= 2, "Need two active Drop Points to test access boundaries"
        manager = connection.execute(text("""
            SELECT staff_id FROM core.dim_staff
            WHERE drop_point_id = :drop_point_id AND role_code = 'MANAGER' AND status = 'ACTIVE'
            LIMIT 1
        """), {"drop_point_id": points[0]["drop_point_id"]}).scalar_one()
        connection.execute(text("""
            INSERT INTO app.app_user
                (user_id, full_name, email, password_hash, role_code, status, must_change_password)
            VALUES (:user_id, 'UI Test Regional', :email,
                    crypt(:password, gen_salt('bf', 12)), 'REGIONAL_MANAGER', 'ACTIVE', FALSE)
        """), {"user_id": user_id, "email": email, "password": password})
        for region in {point["region"] for point in points}:
            connection.execute(text("""
                INSERT INTO app.user_region_access (user_id, region)
                VALUES (:user_id, :region)
            """), {"user_id": user_id, "region": region})
        for point in points:
            connection.execute(text("""
                INSERT INTO app.user_drop_point_access (user_id, drop_point_id, access_type)
                VALUES (:user_id, :drop_point_id, 'VIEW')
            """), {"user_id": user_id, "drop_point_id": point["drop_point_id"]})
        connection.execute(text("""
            INSERT INTO app.app_user
                (user_id, full_name, email, password_hash, role_code, staff_id, status, must_change_password)
            VALUES (:user_id, 'UI Test DP', :email,
                    crypt(:password, gen_salt('bf', 12)), 'DP_MANAGER', :staff_id, 'ACTIVE', TRUE)
        """), {"user_id": dp_user_id, "email": dp_email, "password": dp_password, "staff_id": manager})
        connection.execute(text("""
            INSERT INTO app.user_drop_point_access (user_id, drop_point_id, access_type)
            VALUES (:user_id, :drop_point_id, 'VIEW')
        """), {"user_id": dp_user_id, "drop_point_id": points[0]["drop_point_id"]})
    created = True

    environment = os.environ.copy()
    environment.update(
        TEST_EMAIL=email, TEST_PASSWORD=password,
        TEST_DP_EMAIL=dp_email, TEST_DP_PASSWORD=dp_password,
        TEST_DP_NEW_PASSWORD=dp_new_password,
        TEST_OTHER_DP=points[1]["drop_point_id"],
    )
    subprocess.run(["node", "tests/live_browser.mjs"], cwd=frontend, env=environment, check=True)
except Exception as error:
    print(f"FAIL: {type(error).__name__} during live browser QA")
    raise SystemExit(1)
finally:
    if created:
        with engine.begin() as connection:
            connection.execute(text("DELETE FROM app.app_user WHERE user_id IN (:regional_user, :dp_user)"), {"regional_user": user_id, "dp_user": dp_user_id})

"""Short live API smoke test. Creates and removes isolated demo users."""

import hashlib
import os
import secrets

import httpx
from sqlalchemy import text

from app.db.database import engine


suffix = secrets.token_hex(4).upper()
dp_user = f"TEST-DP-{suffix}"
regional_user = f"TEST-RM-{suffix}"
initial_password = secrets.token_urlsafe(18)
new_password = secrets.token_urlsafe(20)
regional_password = secrets.token_urlsafe(18)


def expect(response, status):
    assert response.status_code == status, (response.request.url.path, response.status_code, response.text[:200])
    return response.json() if response.content else None


try:
    with engine.begin() as connection:
        dps = connection.execute(text("""
            SELECT dp.drop_point_id, dp.region, st.staff_id
            FROM core.dim_drop_point dp
            JOIN core.dim_staff st ON st.drop_point_id = dp.drop_point_id
            WHERE st.role_code = 'MANAGER' AND st.status = 'ACTIVE'
            ORDER BY dp.drop_point_id LIMIT 2
        """)).mappings().all()
        assert len(dps) == 2 and dps[0]["region"] == dps[1]["region"]
        for user_id, role, staff_id, password, must_change in (
            (dp_user, "DP_MANAGER", dps[0]["staff_id"], initial_password, True),
            (regional_user, "REGIONAL_MANAGER", None, regional_password, False),
        ):
            connection.execute(text("""
                INSERT INTO app.app_user
                    (user_id, full_name, email, password_hash, role_code,
                     staff_id, status, must_change_password)
                VALUES
                    (:user_id, 'Auth test', :email,
                     crypt(:password, gen_salt('bf', 12)), :role,
                     :staff_id, 'ACTIVE', :must_change)
            """), {
                "user_id": user_id,
                "email": f"{user_id.lower()}@demo.local",
                "password": password,
                "role": role,
                "staff_id": staff_id,
                "must_change": must_change,
            })
            for dp in dps:
                connection.execute(text("""
                    INSERT INTO app.user_drop_point_access
                        (user_id, drop_point_id, access_type)
                    VALUES (:user_id, :drop_point_id, 'VIEW')
                """), {"user_id": user_id, "drop_point_id": dp["drop_point_id"]})
        connection.execute(text("""
            INSERT INTO app.user_region_access (user_id, region)
            VALUES (:user_id, :region)
        """), {"user_id": regional_user, "region": dps[0]["region"]})

    with httpx.Client(base_url="http://127.0.0.1:8000", timeout=15) as client:
        expect(client.get("/health"), 200)
        expect(client.get("/api/summary"), 401)
        for path in ("/internal/reports/summary", "/internal/reports/daily"):
            expect(client.get(path), 401)
            expect(client.get(path, headers={"X-Internal-Key": "incorrect"}), 401)
            assert expect(client.get(path, headers={
                "X-Internal-Key": os.environ["SIMULATION_API_KEY"],
            }), 200)["count"] == 6
        expect(client.post("/api/auth/login", json={
            "email": f"{dp_user.lower()}@demo.local", "password": "incorrect"
        }), 401)

        login = expect(client.post("/api/auth/login", json={
            "email": f"{dp_user.lower()}@demo.local", "password": initial_password
        }), 200)
        assert login["must_change_password"] is True
        token = login["access_token"]
        with engine.connect() as connection:
            stored = connection.execute(text("""
                SELECT count(*) FROM app.auth_session
                WHERE token_hash = :token_hash AND user_id = :user_id
            """), {
                "token_hash": hashlib.sha256(token.encode()).hexdigest(),
                "user_id": dp_user,
            }).scalar_one()
        assert stored == 1
        client.headers["Authorization"] = f"Bearer {token}"
        expect(client.get("/api/summary"), 403)
        expect(client.post("/api/auth/change-password", json={
            "current_password": initial_password, "new_password": new_password,
        }), 204)
        expect(client.get("/api/auth/me"), 401)
        login = expect(client.post("/api/auth/login", json={
            "email": f"{dp_user.lower()}@demo.local", "password": new_password
        }), 200)
        client.headers["Authorization"] = f"Bearer {login['access_token']}"
        me = expect(client.get("/api/auth/me"), 200)
        assert [dp["drop_point_id"] for dp in me["drop_points"]] == [dps[0]["drop_point_id"]]
        assert expect(client.get("/api/summary"), 200)["count"] == 1
        assert expect(client.get("/api/drop-points"), 200)["count"] == 1
        assert expect(client.get("/api/reports/daily"), 200)["count"] == 1
        pulse = expect(client.get("/api/operations/pulse?days=7"), 200)
        assert pulse["count"] == 7
        assert {row["drop_point_id"] for row in pulse["data"]} == {dps[0]["drop_point_id"]}
        assert expect(client.get(f"/api/drop-points/{dps[0]['drop_point_id']}/parcel-queue"), 200)["count"] >= 0
        expect(client.get(f"/api/drop-points/{dps[1]['drop_point_id']}/pulse"), 403)
        expect(client.get(f"/api/drop-points/{dps[1]['drop_point_id']}/parcel-queue"), 403)
        expect(client.get(f"/api/drop-points/{dps[0]['drop_point_id']}"), 200)
        expect(client.get(f"/api/drop-points/{dps[1]['drop_point_id']}"), 403)
        expect(client.get(f"/api/drop-points/{dps[1]['drop_point_id']}/sellers"), 403)
        expect(client.post("/api/auth/logout"), 204)
        expect(client.get("/api/summary"), 401)

        client.headers.pop("Authorization", None)
        login = expect(client.post("/api/auth/login", json={
            "email": f"{regional_user.lower()}@demo.local", "password": regional_password
        }), 200)
        client.headers["Authorization"] = f"Bearer {login['access_token']}"
        assert expect(client.get("/api/summary"), 200)["count"] == 2
        assert expect(client.get("/api/operations/pulse?days=7"), 200)["count"] == 14
        expect(client.get(f"/api/drop-points/{dps[1]['drop_point_id']}"), 200)
        with engine.begin() as connection:
            connection.execute(text("""
                UPDATE app.user_region_access SET revoked_at = NOW()
                WHERE user_id = :user_id
            """), {"user_id": regional_user})
        assert expect(client.get("/api/summary"), 200)["count"] == 0
        assert expect(client.get("/api/operations/pulse?days=7"), 200)["count"] == 0
        expect(client.get(f"/api/drop-points/{dps[0]['drop_point_id']}"), 403)

    print("PASS: login, password change, sessions, DP/region scope, pulse, parcel queue, internal reports, revocation")
finally:
    with engine.begin() as connection:
        connection.execute(text("""
            DELETE FROM app.app_user WHERE user_id IN (:dp_user, :regional_user)
        """), {"dp_user": dp_user, "regional_user": regional_user})

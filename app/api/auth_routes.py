"""Website authentication and database-backed Drop Point authorization."""

from dataclasses import dataclass
import hashlib
import secrets

from fastapi import APIRouter, Depends, HTTPException, Response
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, Field
from sqlalchemy import text

from app.db.database import engine


router = APIRouter(prefix="/api/auth", tags=["Website authentication"])
bearer = HTTPBearer(auto_error=False)


class LoginRequest(BaseModel):
    email: str = Field(min_length=3, max_length=255)
    password: str = Field(min_length=1, max_length=256)


class PasswordChangeRequest(BaseModel):
    current_password: str = Field(min_length=1, max_length=256)
    new_password: str = Field(min_length=12, max_length=128)


@dataclass(frozen=True)
class Principal:
    user_id: str
    full_name: str
    email: str
    role_code: str
    data_scope: str
    staff_id: str | None
    must_change_password: bool
    token_hash: str


def _token_hash(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
) -> Principal:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise HTTPException(status_code=401, detail="Authentication required")
    token_hash = _token_hash(credentials.credentials)
    with engine.connect() as connection:
        row = connection.execute(
            text("""
                SELECT u.user_id, u.full_name, u.email, u.role_code,
                       r.data_scope, u.staff_id, u.must_change_password
                FROM app.auth_session s
                JOIN app.app_user u ON u.user_id = s.user_id
                JOIN app.app_role r ON r.role_code = u.role_code
                WHERE s.token_hash = :token_hash
                  AND s.revoked_at IS NULL
                  AND s.expires_at > NOW()
                  AND u.status = 'ACTIVE'
                  AND r.is_active = TRUE
                  AND u.role_code IN ('DP_MANAGER', 'REGIONAL_MANAGER')
            """),
            {"token_hash": token_hash},
        ).mappings().first()
    if row is None:
        raise HTTPException(status_code=401, detail="Invalid or expired session")
    return Principal(**dict(row), token_hash=token_hash)


def dashboard_user(user: Principal = Depends(current_user)) -> Principal:
    if user.must_change_password:
        raise HTTPException(status_code=403, detail="Password change required")
    return user


def allowed_drop_points(user: Principal) -> list[dict]:
    """Intersect explicit DP grants with the user's active role and assignment."""
    with engine.connect() as connection:
        rows = connection.execute(
            text("""
                SELECT dp.drop_point_id, dp.drop_point_name, dp.region
                FROM app.user_drop_point_access a
                JOIN core.dim_drop_point dp ON dp.drop_point_id = a.drop_point_id
                WHERE a.user_id = :user_id AND a.revoked_at IS NULL
                  AND a.access_type IN ('VIEW', 'EDIT', 'ADMIN')
                  AND (
                    (:role_code = 'DP_MANAGER' AND :data_scope = 'DROP_POINT'
                     AND EXISTS (
                        SELECT 1 FROM core.dim_staff st
                        WHERE st.staff_id = :staff_id
                          AND st.drop_point_id = dp.drop_point_id
                          AND st.role_code = 'MANAGER'
                          AND st.status = 'ACTIVE'
                     ))
                    OR
                    (:role_code = 'REGIONAL_MANAGER' AND :data_scope = 'REGION'
                     AND EXISTS (
                        SELECT 1 FROM app.user_region_access ra
                        WHERE ra.user_id = :user_id
                          AND ra.region = dp.region
                          AND ra.revoked_at IS NULL
                     ))
                  )
                ORDER BY dp.drop_point_name
            """),
            {
                "user_id": user.user_id,
                "role_code": user.role_code,
                "data_scope": user.data_scope,
                "staff_id": user.staff_id,
            },
        ).mappings().all()
    return [dict(row) for row in rows]


def require_drop_point(user: Principal, drop_point_id: str) -> str:
    requested = drop_point_id.upper()
    if requested not in {row["drop_point_id"] for row in allowed_drop_points(user)}:
        raise HTTPException(status_code=403, detail="Drop Point access denied")
    return requested


@router.post("/login")
def login(request: LoginRequest, response: Response):
    email = request.email.strip().lower()
    with engine.begin() as connection:
        row = connection.execute(
            text("""
                SELECT u.user_id, u.must_change_password,
                       (crypt(:password, u.password_hash) = u.password_hash) AS valid
                FROM app.app_user u
                JOIN app.app_role r ON r.role_code = u.role_code
                WHERE LOWER(u.email) = :email
                  AND u.status = 'ACTIVE' AND r.is_active = TRUE
                  AND u.role_code IN ('DP_MANAGER', 'REGIONAL_MANAGER')
                  AND u.password_hash IS NOT NULL
            """),
            {"email": email, "password": request.password},
        ).mappings().first()
        if row is None or not row["valid"]:
            raise HTTPException(status_code=401, detail="Invalid credentials")
        token = secrets.token_urlsafe(32)
        expires_at = connection.execute(
            text("""
                INSERT INTO app.auth_session (token_hash, user_id, expires_at)
                VALUES (:token_hash, :user_id, NOW() + INTERVAL '8 hours')
                RETURNING expires_at
            """),
            {"token_hash": _token_hash(token), "user_id": row["user_id"]},
        ).scalar_one()
        connection.execute(
            text("UPDATE app.app_user SET last_login_at = NOW() WHERE user_id = :user_id"),
            {"user_id": row["user_id"]},
        )
    response.headers["Cache-Control"] = "no-store"
    return {
        "access_token": token,
        "token_type": "bearer",
        "expires_at": expires_at,
        "must_change_password": row["must_change_password"],
    }


@router.get("/me")
def me(response: Response, user: Principal = Depends(current_user)):
    response.headers["Cache-Control"] = "no-store"
    return {
        "user_id": user.user_id,
        "full_name": user.full_name,
        "email": user.email,
        "role_code": user.role_code,
        "must_change_password": user.must_change_password,
        "drop_points": allowed_drop_points(user),
    }


@router.post("/change-password", status_code=204)
def change_password(
    request: PasswordChangeRequest,
    user: Principal = Depends(current_user),
):
    if len(request.new_password.encode("utf-8")) > 72:
        raise HTTPException(status_code=400, detail="Password exceeds 72 UTF-8 bytes")
    if request.new_password == request.current_password:
        raise HTTPException(status_code=400, detail="Choose a different password")
    with engine.begin() as connection:
        valid = connection.execute(
            text("""
                SELECT crypt(:password, password_hash) = password_hash
                FROM app.app_user WHERE user_id = :user_id AND status = 'ACTIVE'
                FOR UPDATE
            """),
            {"password": request.current_password, "user_id": user.user_id},
        ).scalar_one_or_none()
        if not valid:
            raise HTTPException(status_code=401, detail="Invalid credentials")
        connection.execute(
            text("""
                UPDATE app.app_user
                SET password_hash = crypt(:new_password, gen_salt('bf', 12)),
                    must_change_password = FALSE, updated_at = NOW()
                WHERE user_id = :user_id
            """),
            {"new_password": request.new_password, "user_id": user.user_id},
        )
        connection.execute(
            text("""
                UPDATE app.auth_session SET revoked_at = NOW()
                WHERE user_id = :user_id AND revoked_at IS NULL
            """),
            {"user_id": user.user_id},
        )
    return Response(status_code=204, headers={"Cache-Control": "no-store"})


@router.post("/logout", status_code=204)
def logout(user: Principal = Depends(current_user)):
    with engine.begin() as connection:
        connection.execute(
            text("""
                UPDATE app.auth_session SET revoked_at = NOW()
                WHERE token_hash = :token_hash AND revoked_at IS NULL
            """),
            {"token_hash": user.token_hash},
        )
    return Response(status_code=204, headers={"Cache-Control": "no-store"})

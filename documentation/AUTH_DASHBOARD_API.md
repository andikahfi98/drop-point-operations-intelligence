# Dashboard API for Figma handoff

The dashboard uses a bearer token returned by `POST /api/auth/login`. The token expires after 8 hours and is stored in the database only as a SHA-256 digest. Send it in `Authorization: Bearer <token>` on every dashboard request. Keep it in browser memory and clear it on logout or page close. Do not put it in a URL.

Seeded demo accounts require a password change before dashboard data can be read. After login, inspect `must_change_password`. If true, show the change-password screen; a successful change ends all sessions, so the user signs in again. Passwords are never returned by the API. The local demo has no password reset flow yet.

| Method | Endpoint | Screen / purpose | Access |
| --- | --- | --- | --- |
| `POST` | `/api/auth/login` | Sign in with `{ "email": "...", "password": "..." }`; returns `access_token`, `token_type`, `expires_at`, `must_change_password` | Public |
| `GET` | `/api/auth/me` | User name, role, password-change flag, accessible DP list | Signed in |
| `POST` | `/api/auth/change-password` | `{ "current_password": "...", "new_password": "..." }`; minimum 12 characters and maximum 72 UTF-8 bytes; then sign in again | Signed in |
| `POST` | `/api/auth/logout` | Revoke current session | Signed in |
| `GET` | `/api/summary` | Summary cards and DP status rows | Accessible DPs only |
| `GET` | `/api/operations/pulse?days=7` | Regional daily inbound, outbound, delivered, and revenue trend; `days` may be `7` or `14` | Accessible DPs only |
| `GET` | `/api/drop-points` | DP selector, names, region, manager | Accessible DPs only |
| `GET` | `/api/drop-points/{id}` | DP overview | Assigned DP only |
| `GET` | `/api/drop-points/{id}/pulse?days=7` | Daily trend for one DP; `days` may be `7` or `14` | Assigned DP only |
| `GET` | `/api/drop-points/{id}/parcel-queue` | Up to 100 parcels currently at that DP, with status and age | Assigned DP only |
| `GET` | `/api/drop-points/{id}/sellers` | Seller activity and attention | Assigned DP only |
| `GET` | `/api/drop-points/{id}/parcels` | Parcel flow and top issues | Assigned DP only |
| `GET` | `/api/drop-points/{id}/delivery` | Delivery KPIs and top issues | Assigned DP only |
| `GET` | `/api/drop-points/{id}/seller-pics` | Seller PIC performance | Assigned DP only |
| `GET` | `/api/drop-points/{id}/team` | Manager and operational team | Assigned DP only |
| `GET` | `/api/drop-points/{id}/responsibility` | Status ownership and escalation | Assigned DP only |
| `GET` | `/api/reports/daily` | Daily report rows | Accessible DPs only |

Collections return `{ "count": number, "data": [...] }`. The daily report also includes `business_date`. Parcel, delivery, team, and responsibility details include nested summaries or issue lists. Use `/docs` on the running local API for request forms and call a permitted endpoint to inspect sample JSON. A missing or expired token returns `401`; an active account that must change its password or requests another DP returns `403`.

DP Manager access requires both an active manager staff assignment and an unrevoked DP grant. Regional Manager access requires an unrevoked region grant and an unrevoked DP grant within that region. Every request checks current database grants, so revocation takes effect immediately. Both roles currently have read-only dashboard access.

`POST /api/chat` is the Telegram workflow endpoint and `POST /api/agent/chat` is an internal agent endpoint. Both require the existing `X-Internal-Key` automation credential and are not browser dashboard endpoints. In addition, `/api/chat` accepts operational data requests only from chat IDs listed in `TELEGRAM_REGIONAL_CHAT_IDS`, using the active Regional Manager specified by `TELEGRAM_REGIONAL_USER_ID`. The bot derives its DP scope from that account's current region and DP grants. An unlisted chat or a request for a DP outside those grants is denied. There is no Telegram pairing code or linking flow. The bot can answer daily trend questions using the same daily pulse data as the website. Keep the chat ID and internal key in local environment configuration; do not put them in the frontend. Workflow schedules and triggers are unchanged.

The n8n Intraday and Daily Report workflows read `GET /internal/reports/summary` and `GET /internal/reports/daily` respectively. These local automation routes require `X-Internal-Key` and return the same unfiltered report shapes used by the original scheduled workflows. Browser dashboard endpoints remain scoped by bearer session and current DP/region grants. Do not expose the internal key to the frontend.

For a later GitHub Pages frontend, host FastAPI and PostgreSQL separately behind HTTPS, set an explicit CORS allowlist for the frontend origin, and add public-facing login rate limiting. GitHub Pages cannot run this API or PostgreSQL. The present deployment and tests are local only.

Apply `sql/068_create_auth_sessions.sql` and `sql/069_drop_point_daily_pulse.sql` before deploying the updated API into another local database. The integration smoke test is `tests/test_auth_integration.py`; it creates temporary users and removes them on completion.

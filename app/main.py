from fastapi import FastAPI

from app.api.routes import router
from app.api.simulation_routes import router as simulation_router
from app.api.alert_routes import router as alert_router
from app.api.agent_routes import router as agent_router
from app.api.chat_routes import router as chat_router
from app.api.auth_routes import router as auth_router
from app.api.internal_report_routes import router as internal_report_router


app = FastAPI(
    title="Drop Point Operations Intelligence API",
    description=(
        "Backend API for Drop Point operational monitoring, "
        "reporting, automation, and AI analysis."
    ),
    version="0.2.0",
)

app.include_router(chat_router)
app.include_router(auth_router)
app.include_router(router)
app.include_router(simulation_router)
app.include_router(alert_router)
app.include_router(agent_router)
app.include_router(internal_report_router)

# Telegram chat ingress is webhook-first via n8n. Legacy polling routes are
# intentionally not mounted in the application.


@app.get("/")
def root():
    return {
        "application": "Drop Point Operations Intelligence",
        "status": "running",
        "domain": "expedition_logistics",
        "telegram_ingress": "webhook",
    }

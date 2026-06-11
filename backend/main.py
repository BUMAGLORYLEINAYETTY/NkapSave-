import logging
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
from core.config import settings
from core.database import engine, Base
from services.scheduler import start_scheduler, stop_scheduler
from routers import auth, dashboard, expenses, savings, njangi, njangi_chat, profile, reminders, notifications, momo, nkapbot
# TODO(kyc): re-import `kyc` and re-register its router once the
# replacement verification pipeline (tiered access + auto-verify) lands.
# The router module itself is kept on disk — only the registration is off.
from routers.expenses import budgets_router

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger("nkapsave")


@asynccontextmanager
async def lifespan(app: FastAPI):
    start_scheduler()
    if not settings.is_production:
        # Dev only: auto-create tables, then run idempotent schema migrations.
        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)
        from core.migrations import run_dev_migrations
        await run_dev_migrations(engine)
    logger.info("%s %s started (env=%s)", settings.APP_NAME, settings.APP_VERSION, settings.ENVIRONMENT)
    yield
    stop_scheduler()
    await engine.dispose()


app = FastAPI(lifespan=lifespan, docs_url="/api/docs")

origins = settings.cors_origins
if settings.is_production and not origins:
    raise RuntimeError(
        "ALLOWED_ORIGINS must be set in production. "
        "Set ENVIRONMENT=development to bypass for local work."
    )

cors_kwargs = {
    "allow_credentials": True,
    "allow_methods": ["GET", "POST", "PATCH", "DELETE", "OPTIONS"],
    "allow_headers": ["Authorization", "Content-Type"],
}
if settings.is_production:
    cors_kwargs["allow_origins"] = origins
else:
    # Flutter's dev server (`flutter run -d chrome`) picks a random port on each launch,
    # so match any localhost/127.0.0.1 origin instead of pinning ports.
    cors_kwargs["allow_origin_regex"] = r"http://(localhost|127\.0\.0\.1)(:\d+)?"

app.add_middleware(CORSMiddleware, **cors_kwargs)

app.include_router(auth.router,         prefix="/api/v1")
app.include_router(dashboard.router,    prefix="/api/v1")
app.include_router(expenses.router,     prefix="/api/v1")
app.include_router(savings.router,      prefix="/api/v1")
app.include_router(njangi.router,       prefix="/api/v1")
app.include_router(njangi_chat.router,  prefix="/api/v1")
app.include_router(profile.router,      prefix="/api/v1")
app.include_router(reminders.router,    prefix="/api/v1")
app.include_router(notifications.router, prefix="/api/v1")
app.include_router(momo.router,         prefix="/api/v1")
app.include_router(budgets_router,      prefix="/api/v1")
app.include_router(nkapbot.router,      prefix="/api/v1")
# app.include_router(kyc.router,        prefix="/api/v1")  # disabled — see import note above


@app.get("/api/health")
async def health():
    return {"status": "ok"}

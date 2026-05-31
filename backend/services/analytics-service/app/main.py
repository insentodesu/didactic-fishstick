from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import logging

from app.routers import analytics

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")

app = FastAPI(
    title="ФинАссистент — Analytics Service",
    description="Финансовый диагноз, кредитный светофор, аномалии, прогнозы, AI-чат",
    version="1.0.0",
)

app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True, allow_methods=["*"], allow_headers=["*"])

app.include_router(analytics.router)


@app.get("/health")
async def health():
    return {"status": "ok", "service": "analytics-service"}

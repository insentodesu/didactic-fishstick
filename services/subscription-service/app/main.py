from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.routers import subscriptions

app = FastAPI(title="ФинАссистент — Subscription Service", version="1.0.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True, allow_methods=["*"], allow_headers=["*"])
app.include_router(subscriptions.router)


@app.get("/health")
async def health():
    return {"status": "ok", "service": "subscription-service"}

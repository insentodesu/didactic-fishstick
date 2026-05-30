from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.routers import notifications

app = FastAPI(title="ФинАссистент — Notification Service", version="1.0.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True, allow_methods=["*"], allow_headers=["*"])
app.include_router(notifications.router)


@app.get("/health")
async def health():
    return {"status": "ok", "service": "notification-service"}

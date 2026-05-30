from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.routers import investments

app = FastAPI(title="ФинАссистент — Investment Service", version="1.0.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True, allow_methods=["*"], allow_headers=["*"])
app.include_router(investments.router)


@app.get("/health")
async def health():
    return {"status": "ok", "service": "investment-service"}

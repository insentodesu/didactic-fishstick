from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.routers import gamification

app = FastAPI(
    title="ФинАссистент — Gamification Service",
    description="Тамагочи, стрики, достижения, ежедневные задания, лиги",
    version="1.0.0",
)

app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True, allow_methods=["*"], allow_headers=["*"])
app.include_router(gamification.router)


@app.get("/health")
async def health():
    return {"status": "ok", "service": "gamification-service"}

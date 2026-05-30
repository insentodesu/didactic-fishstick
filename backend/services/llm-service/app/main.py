from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.routers import llm

app = FastAPI(
    title="ФинАссистент — AI Service",
    description="Финансовый AI-ассистент: классификация транзакций, анализ, чат, инсайты.",
    version="1.0.0",
)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True, allow_methods=["*"], allow_headers=["*"])
app.include_router(llm.router)


@app.get("/health")
async def health():
    return {"status": "ok", "service": "ai-service", "model": "finassist-1"}

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.routers import transactions

app = FastAPI(
    title="ФинАссистент — Transaction Service",
    description="Загрузка и анализ банковских выписок, категоризация транзакций",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(transactions.router)


@app.get("/health")
async def health():
    return {"status": "ok", "service": "transaction-service"}

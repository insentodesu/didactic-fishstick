from datetime import date, datetime
from decimal import Decimal
from typing import Optional
from uuid import UUID

from pydantic import BaseModel, field_validator


class UploadStatementResponse(BaseModel):
    statement_id: str
    status: str


class ManualTransactionRequest(BaseModel):
    description: str
    amount: float
    is_income: bool
    category_name: Optional[str] = None
    transaction_date: Optional[datetime] = None


class TransactionResponse(BaseModel):
    id: UUID
    amount: Decimal
    is_income: bool
    merchant_name: str | None
    category_id: int | None
    category: str | None = None
    category_icon: str | None = None
    category_confidence: float | None
    description: str | None
    transaction_date: datetime
    created_at: datetime
    source: str = "bank_statement"

    model_config = {"from_attributes": True}


class TransactionListResponse(BaseModel):
    items: list[TransactionResponse]
    total: int
    page: int
    page_size: int


class TransactionSummaryResponse(BaseModel):
    total_income: Decimal
    total_expense: Decimal
    balance: Decimal
    total_count: int


class CategoryStatsResponse(BaseModel):
    name_ru: str | None
    icon: str | None
    color: str | None
    total: Decimal
    cnt: int

    model_config = {"from_attributes": True}


class MerchantStatsResponse(BaseModel):
    merchant_name: str | None
    total: Decimal
    cnt: int

    model_config = {"from_attributes": True}


class UpdateCategoryRequest(BaseModel):
    category_id: int

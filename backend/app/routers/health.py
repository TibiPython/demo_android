# backend/app/routers/health.py
from fastapi import APIRouter
from app.deps import get_conn

router = APIRouter()

@router.get("/ping")
def ping():
    with get_conn() as conn:
        conn.execute("SELECT 1")
    return {"status": "ok"}

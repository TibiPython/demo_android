# backend/app/routers/debug_mail.py
from fastapi import APIRouter, HTTPException
import os
from app.notifications import send_loan_created_email
from app.deps import get_conn

router = APIRouter(prefix="/debug/mail", tags=["debug"])

def _mask(s: str | None) -> str:
    if not s:
        return ""
    if len(s) <= 6:
        return "***"
    return s[:2] + "…" * (len(s) - 4) + s[-2:]

@router.get("")
def info():
    return {
        "SMTP_HOST": os.getenv("SMTP_HOST"),
        "SMTP_PORT": os.getenv("SMTP_PORT"),
        "SMTP_TLS":  os.getenv("SMTP_TLS"),
        "SMTP_USER": os.getenv("SMTP_USER"),
        "FROM_EMAIL": os.getenv("FROM_EMAIL"),
        "EMAIL_ON_LOAN_CREATED": os.getenv("EMAIL_ON_LOAN_CREATED"),
        "SMTP_PASS_len": len(os.getenv("SMTP_PASS") or 0),  # solo la longitud
        # "SMTP_PASS_masked": _mask(os.getenv("SMTP_PASS")),  # si quieres ver máscara
    }

@router.post("/send")
def send(prestamo_id: int | None = None, cod_cli: str | None = None):
    """
    Envía el correo del préstamo creado desde ESTE PROCESO (sin background), para depurar.
    Usa prestamo_id o, si no lo das, el último préstamo de cod_cli.
    """
    if prestamo_id is None and cod_cli:
        with get_conn() as conn:
            row = conn.execute(
                "SELECT id FROM prestamos WHERE cod_cli=? ORDER BY id DESC LIMIT 1",
                (cod_cli,)
            ).fetchone()
            if row:
                prestamo_id = int(row["id"])
    if prestamo_id is None:
        raise HTTPException(status_code=400, detail="Provee prestamo_id o cod_cli")

    send_loan_created_email(int(prestamo_id))
    return {"status": "sent", "prestamo_id": prestamo_id}

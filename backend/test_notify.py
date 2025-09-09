from pathlib import Path
from dotenv import load_dotenv
from app.notifications import send_loan_created_email
from app.deps import get_conn

ENV = Path(__file__).resolve().parent / ".env"
load_dotenv(ENV, override=True)

with get_conn() as conn:
    row = conn.execute("SELECT id FROM prestamos WHERE cod_cli='005' ORDER BY id DESC LIMIT 1").fetchone()
    if row:
        print("Enviando para prestamo id:", row["id"])
        send_loan_created_email(row["id"])
    else:
        print("No hay prestamos para 005")

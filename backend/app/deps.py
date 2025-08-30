# backend/app/deps.py
from contextlib import contextmanager
import sqlite3
import os
from pathlib import Path
from dotenv import load_dotenv

# Resuelve la ruta por defecto SIEMPRE relativa a este archivo:
# backend/app/deps.py -> backend/  -> backend/data/basedatos.db
BASE_DIR = Path(__file__).resolve().parents[1]
DEFAULT_DB = BASE_DIR / 'data' / 'basedatos.db'

load_dotenv()
DB_PATH = os.getenv("DB_PATH", str(DEFAULT_DB))

@contextmanager
def get_conn():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
    finally:
        conn.commit()
        conn.close()

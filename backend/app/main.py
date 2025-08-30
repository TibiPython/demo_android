from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

# Routers
from .routers import health
from .routers import clientes
from .routers import prestamos
from app.routers import cuotas as cuotas_router  # ✅ usa una sola forma de importar cuotas

# DB
from app.deps import get_conn  # ✅ para la conexión SQLite

app = FastAPI()

# CORS (igual que antes)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------- Migración automática: asegurar columna 'email' en clientes ----------
def ensure_clientes_email_column() -> None:
    """
    Asegura que la tabla 'clientes' tenga la columna 'email'.
    Idempotente: si ya existe, no hace nada.
    """
    with get_conn() as conn:
        cols = [r["name"] for r in conn.execute("PRAGMA table_info(clientes);").fetchall()]
        if "email" not in cols:
            conn.execute("ALTER TABLE clientes ADD COLUMN email TEXT;")
            conn.commit()

@app.on_event("startup")
def _run_startup_migrations():
    ensure_clientes_email_column()
# -------------------------------------------------------------------------------

# Routers
app.include_router(cuotas_router.router, prefix="/cuotas")                 # expone /cuotas
app.include_router(health.router,   prefix="/health",    tags=["Health"])  # /health
app.include_router(clientes.router, prefix="/clientes",  tags=["Clientes"])# /clientes
app.include_router(prestamos.router, prefix="/prestamos", tags=["Prestamos"])  # /prestamos

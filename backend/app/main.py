# backend/app/main.py
# App FastAPI con CORS y manejador global de errores para devolver JSON con 'detail'
from __future__ import annotations

import logging
import traceback
from typing import Any

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

# Importa tus routers existentes
# (Si alguno no existe en tu árbol actual, comenta la línea correspondiente.)
from app.routers import health
from app.routers import clientes
from app.routers import prestamos
from app.routers import cuotas
try:
    from app.routers import debug_mail  # opcional en tu proyecto
except Exception:
    debug_mail = None  # type: ignore

# --------------------------------------------------------------------------------------
# Config básica de app
# --------------------------------------------------------------------------------------
app = FastAPI(title="Demo Android API", version="1.0.0")

# CORS abierto para desarrollo; ajusta si usas dominios específicos
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],            # en producción especifica dominios
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --------------------------------------------------------------------------------------
# Manejador GLOBAL de errores no controlados
# (Evita 'Internal Server Error' en texto plano y expone un JSON con 'detail')
# --------------------------------------------------------------------------------------
logger = logging.getLogger("uvicorn.error")

@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception):
    # Log completo en servidor (no se muestra al cliente)
    tb = "".join(traceback.format_exception(type(exc), exc, exc.__traceback__))
    logger.error("Unhandled exception on %s %s\n%s", request.method, request.url.path, tb)

    # Respuesta amigable para el cliente (tu app lee 'detail')
    return JSONResponse(
        status_code=500,
        content={
            "detail": f"Error interno: {type(exc).__name__}: {str(exc)}"
        },
    )

# --------------------------------------------------------------------------------------
# Rutas/routers
# --------------------------------------------------------------------------------------
@app.get("/")
async def root() -> dict[str, Any]:
    return {"status": "ok"}

# Monta tus routers bajo el prefijo esperado por el front
app.include_router(health.router, prefix="/health", tags=["health"])
app.include_router(clientes.router, prefix="/clientes", tags=["clientes"])
app.include_router(prestamos.router, prefix="/prestamos", tags=["prestamos"])
app.include_router(cuotas.router, prefix="/cuotas", tags=["cuotas"])
if debug_mail:
    app.include_router(debug_mail.router, prefix="/debug", tags=["debug"])

# --------------------------------------------------------------------------------------
# Nota:
# - No se toca la lógica de negocio de ningun router.
# - Solo se añade el handler global para devolver JSON con 'detail' en 500 inesperados.
# - Esto te permitirá ver el mensaje en la app móvil (gracias a http.dart actualizado).
# --------------------------------------------------------------------------------------

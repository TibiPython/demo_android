from fastapi import FastAPI
from app.routers import cuotas as cuotas_router 
from fastapi.middleware.cors import CORSMiddleware
from .routers import health
from .routers import clientes  
from .routers import prestamos
from .routers import cuotas # <-- NUEVO

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.include_router(cuotas_router.router, prefix="/cuotas")  # ← añadir
app.include_router(health.router, prefix="/health", tags=["Health"])
app.include_router(clientes.router, prefix="/clientes", tags=["Clientes"])  # <-- NUEVO
app.include_router(prestamos.router, prefix="/prestamos", tags=["Prestamos"])  # <-- esta línea expone /prestamos
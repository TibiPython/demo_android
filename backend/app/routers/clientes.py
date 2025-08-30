from fastapi import APIRouter, HTTPException, Path
from pydantic import BaseModel, EmailStr, field_validator
from pydantic.types import StringConstraints
from typing import Optional, List, Any, Annotated
from app.deps import get_conn

router = APIRouter()

# ---------- Tipos con validación (Pydantic v2) ----------
NombreStr     = Annotated[str, StringConstraints(strip_whitespace=True, min_length=2, max_length=80)]
CodigoStr     = Annotated[str, StringConstraints(strip_whitespace=True, pattern=r"^\d{1,10}$")]        # '003', '15', etc.
TelefonoStr   = Annotated[str, StringConstraints(strip_whitespace=True, pattern=r"^\+?\d{6,15}$")]     # solo dígitos (+ opcional)
IdentStr      = Annotated[str, StringConstraints(strip_whitespace=True, min_length=3, max_length=30)]
DireccionStr  = Annotated[str, StringConstraints(strip_whitespace=True, min_length=3, max_length=120)]

class ClienteIn(BaseModel):
    # Si el backend autogenera 'codigo', lo dejamos opcional; si te llega, validamos pero NO lo usaremos al insertar.
    codigo: Optional[CodigoStr] = None
    nombre: NombreStr
    identificacion: Optional[IdentStr] = None
    direccion: Optional[DireccionStr] = None
    telefono: Optional[TelefonoStr] = None
    email: Optional[EmailStr] = None

    @field_validator("*", mode="before")
    @classmethod
    def empty_to_none(cls, v):
        if isinstance(v, str) and not v.strip():
            return None
        return v

class ClienteUpdate(BaseModel):
    # PUT parcial: solo actualiza lo que venga no vacío
    nombre: Optional[NombreStr] = None
    identificacion: Optional[IdentStr] = None
    direccion: Optional[DireccionStr] = None
    telefono: Optional[TelefonoStr] = None
    email: Optional[EmailStr] = None

    @field_validator("*", mode="before")
    @classmethod
    def empty_to_none(cls, v):
        if isinstance(v, str) and not v.strip():
            return None
        return v

# ---------- util ----------
def _table_exists(conn, name: str) -> bool:
    r = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?;",
        (name,)
    ).fetchone()
    return r is not None


def _cols(conn, table: str) -> List[str]:
    return [r["name"] for r in conn.execute(f"PRAGMA table_info({table});").fetchall()]


def _generar_siguiente_codigo(conn) -> str:
    """Calcula el siguiente 'codigo' consecutivo con padding de ceros.
    Usa el ancho máximo existente (mínimo 3). Ej.: 001, 002, ..., 010.
    """
    row = conn.execute(
        """
        SELECT 
            COALESCE(MAX(CAST(codigo AS INTEGER)), 0) AS max_num,
            COALESCE(MAX(LENGTH(codigo)), 3)          AS width
        FROM clientes;
        """
    ).fetchone()
    max_num = int(row["max_num"]) if row and row["max_num"] is not None else 0
    width   = int(row["width"])   if row and row["width"]   is not None else 3
    if width < 3:
        width = 3
    return str(max_num + 1).zfill(width)

# ---------- Endpoints ----------
@router.get("")
@router.get("/", include_in_schema=False)
def listar_clientes():
    with get_conn() as conn:
        if not _table_exists(conn, "clientes"):
            return []
        rows = conn.execute("SELECT * FROM clientes ORDER BY id ASC;").fetchall()
        return [{k: r[k] for k in r.keys()} for r in rows]

@router.get("/{id:int}")
def obtener_cliente(id: int = Path(..., ge=1)):
    with get_conn() as conn:
        if not _table_exists(conn, "clientes"):
            raise HTTPException(status_code=404, detail="No existe tabla 'clientes'")
        r = conn.execute("SELECT * FROM clientes WHERE id=?;", (id,)).fetchone()
        if not r:
            raise HTTPException(status_code=404, detail="Cliente no encontrado")
        return {k: r[k] for k in r.keys()}

@router.get("/{id:int}/detalle")
def detalle_cliente(id: int = Path(..., ge=1)):
    return obtener_cliente(id)

@router.post("")
def crear_cliente(payload: ClienteIn):
    with get_conn() as conn:
        if not _table_exists(conn, "clientes"):
            raise HTTPException(status_code=404, detail="No existe tabla 'clientes'")
        cols = _cols(conn, "clientes")

        # === Generar 'codigo' consecutivo automáticamente si la columna existe ===
        codigo_gen: Optional[str] = None
        if "codigo" in cols:
            codigo_gen = _generar_siguiente_codigo(conn)

        # Campos tolerantes: solo insertamos columnas que existan
        fields: List[str] = []
        values: List[Any] = []
        for k in ("codigo", "nombre", "identificacion", "direccion", "telefono", "email"):
            if k in cols:
                fields.append(k)
                if k == "codigo" and codigo_gen is not None:
                    # Ignoramos cualquier 'codigo' provisto por el cliente
                    values.append(codigo_gen)
                else:
                    values.append(getattr(payload, k))

        if not fields:
            raise HTTPException(status_code=400, detail="No hay columnas válidas para insertar")

        placeholders = ",".join(["?"] * len(fields))
        sql = f"INSERT INTO clientes ({','.join(fields)}) VALUES ({placeholders});"
        conn.execute(sql, tuple(values))
        conn.commit()
        new_id = conn.execute("SELECT last_insert_rowid() AS id;").fetchone()["id"]
        r = conn.execute("SELECT * FROM clientes WHERE id=?;", (new_id,)).fetchone()
        return {k: r[k] for k in r.keys()}

@router.put("/{id:int}")
def actualizar_cliente(id: int, payload: ClienteUpdate):
    with get_conn() as conn:
        if not _table_exists(conn, "clientes"):
            raise HTTPException(status_code=404, detail="No existe tabla 'clientes'")
        r0 = conn.execute("SELECT * FROM clientes WHERE id=?;", (id,)).fetchone()
        if not r0:
            raise HTTPException(status_code=404, detail="Cliente no encontrado")

        cols = _cols(conn, "clientes")
        sets: List[str] = []
        vals: List[Any] = []
        for k in ("nombre", "identificacion", "direccion", "telefono", "email"):
            if getattr(payload, k) is not None and k in cols:
                sets.append(f"{k}=?")
                vals.append(getattr(payload, k))
        if not sets:
            return {k: r0[k] for k in r0.keys()}

        vals.append(id)
        conn.execute(f"UPDATE clientes SET {', '.join(sets)} WHERE id=?;", tuple(vals))
        conn.commit()
        r = conn.execute("SELECT * FROM clientes WHERE id=?;", (id,)).fetchone()
        return {k: r[k] for k in r.keys()}

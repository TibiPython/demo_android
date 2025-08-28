from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field, constr
from typing import Optional, List, Dict, Any
from fastapi import Response
import sqlite3
from app.deps import get_conn

router = APIRouter()

# ======== MODELOS ========
NombreStr = constr(strip_whitespace=True, pattern=r"^[A-Za-zÃÃ‰ÃÃ“ÃšÃ¡Ã©Ã­Ã³ÃºÃ‘Ã± ]+$")
TelefonoStr = constr(strip_whitespace=True, pattern=r"^\d+$", min_length=7, max_length=15)

class ClienteIn(BaseModel):
    nombre: NombreStr = Field(..., description="Solo letras y espacios, con tildes.")
    telefono: TelefonoStr = Field(..., description="Solo dÃ­gitos, 7 a 15 caracteres.")

class ClienteOut(BaseModel):
    id: int
    codigo: str
    nombre: str
    telefono: str

class ClientesResp(BaseModel):
    total: int
    items: List[ClienteOut]

# ======== HELPERS ========
def _row_to_cliente(row: sqlite3.Row) -> Dict[str, Any]:
    return {
        "id": row["id"],
        "codigo": row["codigo"],
        "nombre": row["nombre"],
        "telefono": row["telefono"],
    }

def _generar_codigo(conn: sqlite3.Connection) -> str:
    cur = conn.execute(
        "SELECT MAX(CASE WHEN codigo GLOB '[0-9][0-9][0-9]' THEN CAST(codigo AS INTEGER) END) AS maxcod FROM clientes;"
    )
    row = cur.fetchone()
    maxcod = row["maxcod"] if row and row["maxcod"] is not None else 0
    return f"{int(maxcod) + 1:03d}"

# ======== ENDPOINTS ========
@router.get("", response_model=ClientesResp)
def listar_clientes(
    buscar: Optional[str] = Query(None, description="CÃ³digo, nombre o telÃ©fono"),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
):
    offset = (page - 1) * page_size
    with get_conn() as conn:
        if buscar:
            like = f"%{buscar.strip()}%"
            total = conn.execute(
                "SELECT COUNT(*) AS c FROM clientes WHERE codigo LIKE ? OR nombre LIKE ? OR telefono LIKE ?;",
                (like, like, like)
            ).fetchone()["c"]
            rows = conn.execute(
                "SELECT id,codigo,nombre,telefono FROM clientes "
                "WHERE codigo LIKE ? OR nombre LIKE ? OR telefono LIKE ? "
                "ORDER BY codigo ASC LIMIT ? OFFSET ?;",
                (like, like, like, page_size, offset)
            ).fetchall()
        else:
            total = conn.execute("SELECT COUNT(*) AS c FROM clientes;").fetchone()["c"]
            rows = conn.execute(
                "SELECT id,codigo,nombre,telefono FROM clientes "
                "ORDER BY codigo ASC LIMIT ? OFFSET ?;",
                (page_size, offset)
            ).fetchall()

    items = [_row_to_cliente(r) for r in rows]
    return {"total": total, "items": items}

@router.get("/{id}", response_model=ClienteOut)
def obtener_cliente(id: int):
    with get_conn() as conn:
        row = conn.execute(
            "SELECT id,codigo,nombre,telefono FROM clientes WHERE id=?;",
            (id,)
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Cliente no encontrado")
        return _row_to_cliente(row)

@router.post("", response_model=ClienteOut, status_code=201)
def crear_cliente(data: ClienteIn):
    with get_conn() as conn:
        nuevo_codigo = _generar_codigo(conn)
        dup = conn.execute("SELECT 1 FROM clientes WHERE codigo=?;", (nuevo_codigo,)).fetchone()
        if dup:
            raise HTTPException(status_code=409, detail="CÃ³digo de cliente ya existe (intente nuevamente).")

        cur = conn.execute(
            "INSERT INTO clientes (codigo, nombre, telefono) VALUES (?, ?, ?);",
            (nuevo_codigo, data.nombre.strip(), data.telefono.strip())
        )
        new_id = cur.lastrowid
        row = conn.execute("SELECT id,codigo,nombre,telefono FROM clientes WHERE id=?;", (new_id,)).fetchone()
        return _row_to_cliente(row)

@router.put("/{id}", response_model=ClienteOut)
def actualizar_cliente(id: int, data: ClienteIn):
    with get_conn() as conn:
        existe = conn.execute("SELECT 1 FROM clientes WHERE id=?;", (id,)).fetchone()
        if not existe:
            raise HTTPException(status_code=404, detail="Cliente no encontrado")

        conn.execute(
            "UPDATE clientes SET nombre=?, telefono=? WHERE id=?;",
            (data.nombre.strip(), data.telefono.strip(), id)
        )
        row = conn.execute("SELECT id,codigo,nombre,telefono FROM clientes WHERE id=?;", (id,)).fetchone()
        return _row_to_cliente(row)
# --- utilidades para introspecciÃ³n del esquema (evita romper por nombres distintos) ---
def _cols(conn: sqlite3.Connection, table: str):
    return [r["name"] for r in conn.execute(f"PRAGMA table_info({table});").fetchall()]

def _pick(colnames, candidates):
    s = set(colnames)
    for c in candidates:
        if c in s:
            return c
    return None
@router.delete("/{id}", status_code=204)
def eliminar_cliente(id: int):
    with get_conn() as conn:
        cli = conn.execute("SELECT codigo FROM clientes WHERE id=?;", (id,)).fetchone()
        if not cli:
            raise HTTPException(status_code=404, detail="Cliente no encontrado")

        # Detectar columnas reales en 'prestamos' para verificar asociaciÃ³n
        try:
            prest_cols = _cols(conn, "prestamos")
        except Exception:
            prest_cols = []

        fk_id_col = _pick(prest_cols, ["cliente_id", "id_cliente", "cliente"])
        fk_cod_col = _pick(prest_cols, ["cod_cli", "codigo_cliente"])

        # Construir consulta segura segÃºn columnas existentes
        where_parts = []
        params = []
        if fk_id_col:
            where_parts.append(f"{fk_id_col}=?")
            params.append(id)
        if fk_cod_col:
            where_parts.append(f"{fk_cod_col}=?")
            params.append(cli["codigo"])

        count = 0
        if where_parts:
            q = f"SELECT COUNT(*) AS c FROM prestamos WHERE {' OR '.join(where_parts)};"
            count = conn.execute(q, tuple(params)).fetchone()["c"]

        if count > 0:
            raise HTTPException(
                status_code=409,
                detail="Cliente tiene prÃ©stamos asociados. La eliminaciÃ³n completa se realizarÃ¡ en PASO 4 (operaciones protegidas)."
            )

        conn.execute("DELETE FROM clientes WHERE id=?;", (id,))
        return Response(status_code=204)

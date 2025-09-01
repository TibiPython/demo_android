from fastapi import APIRouter, HTTPException, Query
from typing import List, Optional, Dict, Any, Literal, Annotated
from pydantic import BaseModel, Field, field_validator, AliasChoices
from pydantic.types import StringConstraints
from datetime import date, timedelta, datetime
from app.deps import get_conn

router = APIRouter()

# -------- util --------
def _table_exists(conn, name: str) -> bool:
    r = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?;", (name,)
    ).fetchone()
    return r is not None

def _cols(conn, table: str) -> List[str]:
    return [r["name"] for r in conn.execute(f"PRAGMA table_info({table});").fetchall()]

def _pick(cand: List[str], cols: List[str]) -> Optional[str]:
    s = set(cols)
    for c in cand:
        if c in s:
            return c
    return None

def _add_months(d: date, months: int) -> date:
    y = d.year + (d.month - 1 + months) // 12
    m = (d.month - 1 + months) % 12 + 1
    dim = [31, 29 if (y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)) else 28,
           31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1]
    day = min(d.day, dim)
    return date(y, m, day)

def _cuota_row_to_dict(row, cols_q: List[str]) -> Dict[str, Any]:
    num_col   = "cuota_numero" if "cuota_numero" in cols_q else _pick(["numero"], cols_q) or "cuota_numero"
    fecha_col = "fecha_vencimiento" if "fecha_vencimiento" in cols_q else _pick(["fecha","vencimiento"], cols_q) or "fecha_vencimiento"
    iap_col   = _pick(["interes_a_pagar","interes_calculado","interes"], cols_q) or "interes_a_pagar"
    ipg_col   = _pick(["interes_pagado","interes_pagado_acum"], cols_q) or "interes_pagado"
    est_col   = _pick(["estado","estatus"], cols_q) or "estado"
    return {
        "id": row["id"],
        "numero": row[num_col],
        "fecha_vencimiento": row[fecha_col],
        "interes_a_pagar": float(row[iap_col]) if row[iap_col] is not None else 0.0,
        "interes_pagado": float(row[ipg_col]) if row[ipg_col] is not None else 0.0,
        "estado": row[est_col] or "PENDIENTE",
    }

def _prestamo_item_row_to_dict(row) -> Dict[str, Any]:
    d = {
        "id": row["id"],
        "monto": row["monto"],
        "modalidad": row["modalidad"],
        "fecha_inicio": row["fecha_inicio"],
        "num_cuotas": row["num_cuotas"],
        "tasa_interes": row["tasa_interes"],
        "estado": row["estado"] if "estado" in row.keys() else "PENDIENTE",
        "cliente": {"id": None, "codigo": None, "nombre": None},
    }
    if "cliente_id" in row.keys():
        d["cliente"]["id"] = row["cliente_id"]
    if "cliente_codigo" in row.keys():
        d["cliente"]["codigo"] = row["cliente_codigo"]
    if "cliente_nombre" in row.keys():
        d["cliente"]["nombre"] = row["cliente_nombre"]
    if "p_cod_cli" in row.keys() and d["cliente"]["codigo"] is None:
        d["cliente"]["codigo"] = row["p_cod_cli"]
    return d

# -------- modelos --------
class PrestamoIn(BaseModel):
    cod_cli: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1)]
    importe_credito: Annotated[float, Field(gt=0, validation_alias=AliasChoices("importe_credito", "monto"))]
    tasa_interes:   Annotated[float, Field(ge=0, validation_alias=AliasChoices("tasa_interes", "tasa"))]
    modalidad: Literal["Mensual", "Quincenal"]
    numero_cuotas:  Annotated[int, Field(gt=0, validation_alias=AliasChoices("numero_cuotas", "num_cuotas"))]
    fecha_inicio:   Annotated[date, Field(validation_alias=AliasChoices("fecha_inicio", "fecha_credito"))]

    @field_validator("cod_cli", mode="before")
    @classmethod
    def _trim_code(cls, v):
        if isinstance(v, str):
            v = v.strip()
        if not v:
            raise ValueError("cod_cli requerido")
        return v

    @field_validator("modalidad", mode="before")
    @classmethod
    def _norm_modalidad(cls, v):
        if isinstance(v, str):
            s = v.strip().lower()
            if s.startswith("men"):
                return "Mensual"
            if s.startswith("quin"):
                return "Quincenal"
        return v

# -------- GET /prestamos --------
@router.get("")
@router.get("/", include_in_schema=False)
def listar_prestamos(
    cod_cli: Optional[str] = Query(default=None, description="Filtra por código de cliente"),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=200),
):
    with get_conn() as conn:
        if not _table_exists(conn, "prestamos"):
            return {"total": 0, "items": []}

        has_clientes = _table_exists(conn, "clientes")
        has_cuotas = _table_exists(conn, "cuotas")

        cols_p = _cols(conn, "prestamos")
        cols_c = _cols(conn, "clientes") if has_clientes else []
        cols_q = _cols(conn, "cuotas") if has_cuotas else []

        can_join_by_code = ("cod_cli" in cols_p) and ("codigo" in cols_c)
        join_cond = "p.cod_cli = c.codigo" if (has_clientes and can_join_by_code) else None
        do_join = join_cond is not None

        where_parts: List[str] = []
        params: List[Any] = []
        if cod_cli and cod_cli.strip():
            cod_cli = cod_cli.strip()
            if do_join:
                where_parts.append("c.codigo LIKE ?")
                params.append(f"%{cod_cli}%")
            elif "cod_cli" in cols_p:
                where_parts.append("p.cod_cli LIKE ?")
                params.append(f"%{cod_cli}%")
        where_sql = (" WHERE " + " AND ".join(where_parts)) if where_parts else ""

        # ---- SELECT base (alias hacia el front)
        select_cols = (
            "p.id, p.importe_credito AS monto, p.modalidad, "
            "p.fecha_credito AS fecha_inicio, p.num_cuotas, p.tasa_interes"
        )
        if do_join:
            select_cols += ", c.id AS cliente_id, c.codigo AS cliente_codigo, c.nombre AS cliente_nombre"
        else:
            select_cols += ", p.cod_cli AS p_cod_cli"

        # ---- Estado calculado también en la lista
        estado_sql = "'PENDIENTE' AS estado"
        if has_cuotas:
            fk_q = _pick(["id_prestamo","prestamo_id"], cols_q) or "id_prestamo"
            fecha_col = "fecha_vencimiento" if "fecha_vencimiento" in cols_q else _pick(["fecha","vencimiento"], cols_q) or "fecha_vencimiento"
            estado_sql = f"""
            CASE
              WHEN EXISTS (SELECT 1 FROM cuotas q WHERE q.{fk_q}=p.id)
                   AND NOT EXISTS (SELECT 1 FROM cuotas q WHERE q.{fk_q}=p.id AND UPPER(COALESCE(q.estado,''))<>'PAGADO')
                THEN 'PAGADO'
              WHEN EXISTS (SELECT 1 FROM cuotas q 
                           WHERE q.{fk_q}=p.id 
                             AND UPPER(COALESCE(q.estado,''))<>'PAGADO' 
                             AND DATE(q.{fecha_col}) < DATE('now'))
                THEN 'VENCIDO'
              ELSE 'PENDIENTE'
            END AS estado
            """
        select_cols = f"{select_cols}, {estado_sql}"

        # ---- total
        if do_join:
            q_total = f"SELECT COUNT(*) AS c FROM prestamos p JOIN clientes c ON {join_cond}{where_sql};"
        else:
            q_total = f"SELECT COUNT(*) AS c FROM prestamos p{where_sql};"
        total = conn.execute(q_total, tuple(params)).fetchone()["c"]

        # ---- query paginada
        if do_join:
            q = f"SELECT {select_cols} FROM prestamos p JOIN clientes c ON {join_cond}{where_sql} ORDER BY p.id DESC LIMIT ? OFFSET ?;"
        else:
            q = f"SELECT {select_cols} FROM prestamos p{where_sql} ORDER BY p.id DESC LIMIT ? OFFSET ?;"

        rows = conn.execute(q, tuple(params + [page_size, (page - 1) * page_size])).fetchall()
        items = [_prestamo_item_row_to_dict(r) for r in rows]
        return {"total": total, "items": items}

# -------- GET /prestamos/{id} --------
@router.get("/{id}")
def obtener_prestamo(id: int):
    with get_conn() as conn:
        if not _table_exists(conn, "prestamos"):
            raise HTTPException(status_code=404, detail="No existe tabla 'prestamos'")

        has_clientes = _table_exists(conn, "clientes")
        cols_p = _cols(conn, "prestamos")
        cols_c = _cols(conn, "clientes") if has_clientes else []

        can_join_by_code = ("cod_cli" in cols_p) and ("codigo" in cols_c)
        join_cond = "p.cod_cli = c.codigo" if (has_clientes and can_join_by_code) else None
        do_join = join_cond is not None

        select_cols = (
            "p.id, p.importe_credito AS monto, p.modalidad, "
            "p.fecha_credito AS fecha_inicio, p.num_cuotas, p.tasa_interes"
        )
        if do_join:
            select_cols += ", c.id AS cliente_id, c.codigo AS cliente_codigo, c.nombre AS cliente_nombre"

        if do_join:
            q = f"SELECT {select_cols} FROM prestamos p JOIN clientes c ON {join_cond} WHERE p.id = ?;"
        else:
            q = f"SELECT {select_cols}, p.cod_cli AS p_cod_cli FROM prestamos p WHERE p.id = ?;"

        row = conn.execute(q, (id,)).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Préstamo no encontrado")

        out = _prestamo_item_row_to_dict(row)

        # completar cliente si no hubo JOIN
        if not do_join and has_clientes and out["cliente"]["codigo"]:
            cli = conn.execute(
                "SELECT id, codigo, nombre FROM clientes WHERE codigo=?;",
                (out["cliente"]["codigo"],),
            ).fetchone()
            if cli:
                out["cliente"] = {"id": cli["id"], "codigo": cli["codigo"], "nombre": cli["nombre"]}

        # cuotas
        cuotas: List[Dict[str, Any]] = []
        if _table_exists(conn, "cuotas"):
            cols_q = _cols(conn, "cuotas")
            fk_q = _pick(["id_prestamo","prestamo_id"], cols_q) or "id_prestamo"
            num_col = "cuota_numero" if "cuota_numero" in cols_q else "numero"
            rows_q = conn.execute(
                f"SELECT * FROM cuotas WHERE {fk_q}=? ORDER BY {num_col} ASC;", (id,)
            ).fetchall()
            cuotas = [_cuota_row_to_dict(r, cols_q) for r in rows_q]

        # estado
        estado = "PENDIENTE"
        try:
            todas_pagadas = bool(cuotas) and all(str(c.get("estado","")).upper()=="PAGADO" for c in cuotas)
            vencido = False
            hoy = date.today()
            for c in cuotas:
                if str(c.get("estado","")).upper()=="PAGADO": 
                    continue
                fv_raw = c.get("fecha_vencimiento")
                if isinstance(fv_raw, str) and datetime.fromisoformat(fv_raw).date() < hoy:
                    vencido = True
                    break
            if todas_pagadas:
                estado = "PAGADO"
            elif vencido:
                estado = "VENCIDO"
        except Exception:
            estado = "PENDIENTE"

        return {
            "id": out["id"],
            "cliente": out["cliente"],
            "monto": out["monto"],
            "modalidad": out["modalidad"],
            "fecha_inicio": out["fecha_inicio"],
            "num_cuotas": out["num_cuotas"],
            "tasa_interes": out["tasa_interes"],
            "estado": estado,
            "cuotas": cuotas,
        }

# -------- POST /prestamos --------
@router.post("")
@router.post("/", include_in_schema=False)
def crear_prestamo(data: PrestamoIn):
    with get_conn() as conn:
        if not _table_exists(conn, "prestamos"):
            raise HTTPException(status_code=500, detail="No existe tabla 'prestamos'")
        if not _table_exists(conn, "clientes"):
            raise HTTPException(status_code=400, detail="No existe tabla 'clientes'")

        cli = conn.execute(
            "SELECT id, codigo, nombre FROM clientes WHERE codigo=?;",
            (data.cod_cli.strip(),)
        ).fetchone()
        if not cli:
            raise HTTPException(status_code=404, detail="Cliente no encontrado")

        mod = "Mensual" if data.modalidad.strip().lower().startswith("mensual") else "Quincenal"

        cur = conn.execute(
            "INSERT INTO prestamos (cod_cli, importe_credito, modalidad, fecha_credito, num_cuotas, tasa_interes) "
            "VALUES (?, ?, ?, ?, ?, ?);",
            (
                data.cod_cli.strip(),
                float(data.importe_credito),
                mod,
                data.fecha_inicio.isoformat(),
                int(data.numero_cuotas),
                float(data.tasa_interes),
            ),
        )
        prestamo_id = cur.lastrowid

        if _table_exists(conn, "cuotas"):
            cols_q = _cols(conn, "cuotas")
            fk_q = _pick(["id_prestamo","prestamo_id"], cols_q) or "id_prestamo"
            num_col = "cuota_numero" if "cuota_numero" in cols_q else "numero"
            fecha_col = "fecha_vencimiento" if "fecha_vencimiento" in cols_q else "fecha"

            tasa_cuota = float(data.tasa_interes) if mod == "Mensual" else float(data.tasa_interes) / 2.0
            interes_por_cuota = round(float(data.importe_credito) * (tasa_cuota / 100.0), 2)

            for i in range(1, data.numero_cuotas + 1):
                if mod == "Mensual":
                    fven = _add_months(data.fecha_inicio, i)
                else:
                    fven = data.fecha_inicio + timedelta(days=15 * i)

                conn.execute(
                    f"INSERT INTO cuotas ({fk_q}, {num_col}, {fecha_col}, interes_a_pagar, interes_pagado, estado) "
                    "VALUES (?, ?, ?, ?, ?, ?);",
                    (prestamo_id, i, fven.isoformat(), interes_por_cuota, 0.0, "PENDIENTE"),
                )

        row = conn.execute(
            "SELECT p.id, p.importe_credito AS monto, p.modalidad, p.fecha_credito AS fecha_inicio, "
            "p.num_cuotas, p.tasa_interes, c.id AS cliente_id, c.codigo AS cliente_codigo, c.nombre AS cliente_nombre "
            "FROM prestamos p JOIN clientes c ON p.cod_cli = c.codigo WHERE p.id=?;",
            (prestamo_id,),
        ).fetchone()

        if not row:
            raise HTTPException(status_code=500, detail="Error al recuperar el préstamo recién creado")

        cuotas: List[Dict[str, Any]] = []
        if _table_exists(conn, "cuotas"):
            cols_q = _cols(conn, "cuotas")
            fk_q = _pick(["id_prestamo","prestamo_id"], cols_q) or "id_prestamo"
            num_col = "cuota_numero" if "cuota_numero" in cols_q else "numero"
            rows_q = conn.execute(
                f"SELECT * FROM cuotas WHERE {fk_q}=? ORDER BY {num_col} ASC;", (prestamo_id,)
            ).fetchall()
            cuotas = [_cuota_row_to_dict(r, cols_q) for r in rows_q]

        return {
            "id": row["id"],
            "cliente": {"id": row["cliente_id"], "codigo": row["cliente_codigo"], "nombre": row["cliente_nombre"]},
            "monto": row["monto"],
            "modalidad": row["modalidad"],
            "fecha_inicio": row["fecha_inicio"],
            "num_cuotas": row["num_cuotas"],
            "tasa_interes": row["tasa_interes"],
            "estado": "PENDIENTE",
            "cuotas": cuotas,
        }

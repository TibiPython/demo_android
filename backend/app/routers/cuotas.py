# app/routers/cuotas.py
from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field
from typing import Optional, List, Any, Dict
from datetime import date, datetime
import csv
from pathlib import Path
from app.deps import get_conn

router = APIRouter()  # prefix se agrega en app.main

# ---------- utilidades ----------

def _table_exists(conn, name: str) -> bool:
    r = conn.execute("SELECT name FROM sqlite_master WHERE type='table' AND name=?;", (name,)).fetchone()
    return r is not None


def _cols(conn, table: str) -> List[str]:
    return [r["name"] for r in conn.execute(f"PRAGMA table_info({table});").fetchall()]


def _pick(cols: List[str], candidates: List[str]) -> Optional[str]:
    s = set(cols)
    for c in candidates:
        if c in s:
            return c
    return None


def _db_dir(conn) -> Path:
    row = conn.execute("PRAGMA database_list;").fetchone()
    fpath = row["file"] if row and "file" in row.keys() else None
    return Path(fpath).resolve().parent if fpath else Path.cwd()

# ---------- mapping columnas (cuotas) ----------

def _cuota_mapping(conn) -> Dict[str, str]:
    cols = _cols(conn, "cuotas")
    return {
        "id": "id",
        "fk_prestamo": _pick(cols, ["id_prestamo", "prestamo_id"]) or "id_prestamo",
        "cod_cli": _pick(cols, ["cod_cli", "codigo_cliente"]) or "cod_cli",
        "nombre_cliente": _pick(cols, ["nombre_cliente"]) or "nombre_cliente",
        "modalidad": _pick(cols, ["modalidad"]) or "modalidad",
        "numero": _pick(cols, ["cuota_numero", "numero"]) or "cuota_numero",
        "venc": _pick(cols, ["fecha_vencimiento", "fecha"]) or "fecha_vencimiento",
        "interes_a_pagar": _pick(cols, ["interes_a_pagar", "interes"]) or "interes_a_pagar",
        "fecha_pago": _pick(cols, ["fecha_pago"]) or "fecha_pago",
        "estado": _pick(cols, ["estado"]) or "estado",
        "dias_mora": _pick(cols, ["dias_mora"]) or "dias_mora",
        "abono_capital": _pick(cols, ["abono_capital"]) or "abono_capital",
        "interes_pagado": _pick(cols, ["interes_pagado"]) or "interes_pagado",
    }

# ---------- helper seguro para sqlite3.Row ----------

def _row_to_cuota(row, m) -> Dict[str, Any]:
    """
    Convierte un sqlite3.Row en dict sin usar row.get (sqlite3.Row no lo implementa).
    """
    def has(col: str) -> bool:
        try:
            return col in row.keys()
        except Exception:
            return False

    def fnum(x):
        try:
            return float(x) if x is not None else None
        except Exception:
            return None

    def fint(x):
        try:
            return int(x) if x is not None else None
        except Exception:
            return None

    return {
        "id": row["id"],
        "id_prestamo": row[m["fk_prestamo"]] if has(m["fk_prestamo"]) else None,
        "cod_cli": row[m["cod_cli"]] if has(m["cod_cli"]) else None,
        "nombre_cliente": row[m["nombre_cliente"]] if has(m["nombre_cliente"]) else None,
        "modalidad": row[m["modalidad"]] if has(m["modalidad"]) else None,
        "cuota_numero": fint(row[m["numero"]] if has(m["numero"]) else None),
        "fecha_vencimiento": row[m["venc"]] if has(m["venc"]) else None,
        "interes_a_pagar": fnum(row[m["interes_a_pagar"]] if has(m["interes_a_pagar"]) else None),
        "fecha_pago": row[m["fecha_pago"]] if has(m["fecha_pago"]) else None,
        "estado": row[m["estado"]] if has(m["estado"]) else None,
        "dias_mora": fint(row[m["dias_mora"]] if has(m["dias_mora"]) else None),
        "abono_capital": fnum(row[m["abono_capital"]] if has(m["abono_capital"]) else None),
        "interes_pagado": fnum(row[m["interes_pagado"]] if has(m["interes_pagado"]) else None),
    }

# ---------- modelos ----------

class PagoInput(BaseModel):
    interes_pagado: float = Field(ge=0)
    fecha_pago: Optional[str] = Field(default=None, description="YYYY-MM-DD; default: hoy")


class AbonoCapitalInput(BaseModel):
    monto: float = Field(gt=0)
    fecha: Optional[str] = Field(default=None, description="YYYY-MM-DD; default: hoy")


class PrestamoResumen(BaseModel):
    id: int
    nombre_cliente: Optional[str]
    vence_ultima_cuota: Optional[str]
    estado: str
    modalidad: Optional[str]
    importe_credito: Optional[float]
    tasa_interes: Optional[float]
    total_interes_a_pagar: float
    total_abonos_capital: float
    capital_pendiente: float


# ---------- NUEVO: Resumen de préstamos (definido ANTES de rutas con {id}) ----------

@router.get("/resumen-prestamos")
def resumen_prestamos():
    """Resumen por préstamo (dinámico según columnas reales y tolerante a 'abonos_capital' ausente)."""
    hoy = date.today().isoformat()
    with get_conn() as conn:
        if not (_table_exists(conn, "prestamos") and _table_exists(conn, "cuotas")):
            return []

        m = _cuota_mapping(conn)  # columnas de 'cuotas'
        cols_cuotas = _cols(conn, "cuotas")

        fk = m["fk_prestamo"]
        venc = m["venc"]
        interes_col = m["interes_a_pagar"]
        # nombre_cliente puede no existir en 'cuotas'
        nombre_cli_col = m["nombre_cliente"] if m["nombre_cliente"] in cols_cuotas else None

        # ¿existe tabla abonos_capital?
        abonos_existe = _table_exists(conn, "abonos_capital")
        ab_sum_expr = (
            "COALESCE((SELECT SUM(a.monto) FROM abonos_capital a WHERE a.id_prestamo=p.id), 0)"
            if abonos_existe else "0"
        )

        # total de intereses con la columna real
        total_interes_expr = f"COALESCE((SELECT SUM(c2.{interes_col}) FROM cuotas c2 WHERE c2.{fk}=p.id), 0)"

        # nombre cliente: prioriza clientes.nombre y cae a cuotas.<nombre_cliente> si existe
        nombre_expr = (
            f"COALESCE(MAX(cl.nombre), MAX(cu.{nombre_cli_col}))"
            if nombre_cli_col else "MAX(cl.nombre)"
        )

        sql = f"""
        SELECT
            p.id AS id,
            {nombre_expr} AS nombre_cliente,
            MAX(date(cu.{venc})) AS vence_ultima_cuota,
            p.modalidad AS modalidad,
            p.importe_credito AS importe_credito,
            p.tasa_interes AS tasa_interes,
            {total_interes_expr} AS total_interes_a_pagar,
            {ab_sum_expr} AS total_abonos_capital,
            CASE
                WHEN EXISTS (
                    SELECT 1 FROM cuotas c2
                    WHERE c2.{fk} = p.id
                      AND c2.estado = 'PENDIENTE'
                      AND date(c2.{venc}) < date(?)
                ) THEN 'VENCIDO'
                WHEN (
                    SELECT COUNT(*) FROM cuotas c3 WHERE c3.{fk}=p.id AND c3.estado='PAGADO'
                ) = (
                    SELECT COUNT(*) FROM cuotas c4 WHERE c4.{fk}=p.id
                ) AND (
                    (p.importe_credito - {ab_sum_expr}) > 0
                ) THEN 'VENCIDO'
                WHEN (
                    SELECT COUNT(*) FROM cuotas c5 WHERE c5.{fk}=p.id AND c5.estado='PAGADO'
                ) = (
                    SELECT COUNT(*) FROM cuotas c6 WHERE c6.{fk}=p.id
                ) AND (
                    (p.importe_credito - {ab_sum_expr}) <= 0
                ) THEN 'PAGADO'
                ELSE 'PENDIENTE'
            END AS estado,
            (p.importe_credito - {ab_sum_expr}) AS capital_pendiente
        FROM prestamos p
        LEFT JOIN cuotas cu ON cu.{fk}=p.id
        LEFT JOIN clientes cl ON cl.codigo = p.cod_cli
        GROUP BY p.id
        ORDER BY p.id ASC
        """
        rows = conn.execute(sql, (hoy,)).fetchall()
        # devolvemos dicts simples
        return [{k: r[k] for k in r.keys()} for r in rows]


@router.get("/prestamo/{prestamo_id:int}/resumen")
def resumen_de_prestamo(prestamo_id: int):
    """
    Resumen + lista de cuotas de un préstamo.
    - Usa mapping dinámico.
    - Calcula 'dias_mora' si la cuota está 'PENDIENTE'.
    - Tolera que 'abonos_capital' no exista.
    """
    with get_conn() as conn:
        if not (_table_exists(conn, "prestamos") and _table_exists(conn, "cuotas")):
            raise HTTPException(status_code=404, detail="Faltan tablas requeridas")

        m = _cuota_mapping(conn)
        cols_cuotas = _cols(conn, "cuotas")

        fk = m["fk_prestamo"]
        venc = m["venc"]
        interes_col = m["interes_a_pagar"]
        nombre_cli_col = m["nombre_cliente"] if m["nombre_cliente"] in cols_cuotas else None

        abonos_existe = _table_exists(conn, "abonos_capital")
        ab_sum_expr = (
            "COALESCE((SELECT SUM(monto) FROM abonos_capital a WHERE a.id_prestamo=p.id),0)"
            if abonos_existe else "0"
        )
        total_interes_expr = f"COALESCE((SELECT SUM(cu2.{interes_col}) FROM cuotas cu2 WHERE cu2.{fk}=p.id), 0)"
        nombre_expr = (
            f"COALESCE(MAX(cl.nombre), MAX(cu.{nombre_cli_col}))" if nombre_cli_col else "MAX(cl.nombre)"
        )

        res_sql = f"""
        SELECT
            p.id AS id,
            {nombre_expr} AS nombre_cliente,
            MAX(date(cu.{venc})) AS vence_ultima_cuota,
            p.modalidad AS modalidad,
            p.importe_credito AS importe_credito,
            p.tasa_interes AS tasa_interes,
            {total_interes_expr} AS total_interes_a_pagar,
            {ab_sum_expr} AS total_abonos_capital,
            (p.importe_credito - {ab_sum_expr}) AS capital_pendiente
        FROM prestamos p
        LEFT JOIN cuotas cu ON cu.{fk}=p.id
        LEFT JOIN clientes cl ON cl.codigo = p.cod_cli
        WHERE p.id = ?
        GROUP BY p.id
        """
        rr = conn.execute(res_sql, (prestamo_id,)).fetchone()
        if not rr:
            raise HTTPException(status_code=404, detail="Préstamo no encontrado")

        resumen = {k: rr[k] for k in rr.keys()}

        cu_sql = f"SELECT * FROM cuotas WHERE {fk}=? ORDER BY {m['numero']};"
        cuotas = conn.execute(cu_sql, (prestamo_id,)).fetchall()
        cu_out: List[Dict[str, Any]] = []
        for c in cuotas:
            d = _row_to_cuota(c, m)      # usa nombres reales de columnas
            # Normaliza y calcula mora si está PENDIENTE
            try:
                fv_raw = d.get("fecha_vencimiento")
                if fv_raw and d.get("estado") == "PENDIENTE":
                    try:
                        fv = datetime.strptime(fv_raw, "%Y-%m-%d").date()
                    except ValueError:
                        fv = datetime.fromisoformat(fv_raw).date()
                    d["dias_mora"] = max((date.today() - fv).days, 0)
            except Exception:
                pass
            cu_out.append(d)

        return {"resumen": resumen, "cuotas": cu_out}

# ---------- Endpoints estándar (listar, obtener, pagar, abono) ----------

@router.get("")
@router.get("/", include_in_schema=False)
def listar_cuotas(cod_cli: Optional[str] = Query(default=None),
                  estado: Optional[str] = Query(default=None, pattern=r"^(PENDIENTE|PAGADO)$"),
                  vencidas: bool = Query(default=False),
                  id_prestamo: Optional[int] = Query(default=None)):
    with get_conn() as conn:
        if not _table_exists(conn, "cuotas"):
            return []
        m = _cuota_mapping(conn)
        sql = "SELECT * FROM cuotas WHERE 1=1"
        params: List[Any] = []
        if cod_cli:
            sql += f" AND {m['cod_cli']} = ?"
            params.append(cod_cli)
        if estado:
            sql += f" AND {m['estado']} = ?"
            params.append(estado)
        if id_prestamo is not None:
            sql += f" AND {m['fk_prestamo']} = ?"
            params.append(id_prestamo)
        if vencidas:
            hoy = date.today().isoformat()
            sql += f" AND {m['estado']} = 'PENDIENTE' AND date({m['venc']}) < date(?)"
            params.append(hoy)
        sql += f" ORDER BY {m['fk_prestamo']}, {m['numero']}"
        rows = conn.execute(sql, tuple(params)).fetchall()
        return [_row_to_cuota(r, m) for r in rows]


@router.get("/{cuota_id:int}")
def obtener_cuota(cuota_id: int):
    with get_conn() as conn:
        if not _table_exists(conn, "cuotas"):
            raise HTTPException(status_code=404, detail="No existe tabla 'cuotas'")
        m = _cuota_mapping(conn)
        row = conn.execute("SELECT * FROM cuotas WHERE id = ?", (cuota_id,)).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Cuota no encontrada")
        return _row_to_cuota(row, m)


@router.post("/{cuota_id:int}/pago")
def registrar_pago(cuota_id: int, payload: PagoInput):
    fp = payload.fecha_pago or date.today().isoformat()
    with get_conn() as conn:
        if not _table_exists(conn, "cuotas"):
            raise HTTPException(status_code=404, detail="No existe tabla 'cuotas'")
        m = _cuota_mapping(conn)
        row = conn.execute("SELECT * FROM cuotas WHERE id=?;", (cuota_id,)).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Cuota no encontrada")
        dias_mora = 0
        try:
            fv = datetime.strptime(row[m["venc"]], "%Y-%m-%d").date() if row[m["venc"]] else None
            f_pago = datetime.strptime(fp, "%Y-%m-%d").date()
            if fv:
                dias_mora = max((f_pago - fv).days, 0)
        except Exception:
            dias_mora = 0
        conn.execute(
            f"""
            UPDATE cuotas SET
                {m['estado']} = 'PAGADO',
                {m['fecha_pago']} = ?,
                {m['interes_pagado']} = ?,
                {m['dias_mora']} = ?
            WHERE id = ?
            """,
            (fp, float(payload.interes_pagado), int(dias_mora), cuota_id)
        )
        conn.commit()
        row = conn.execute("SELECT * FROM cuotas WHERE id=?;", (cuota_id,)).fetchone()
        return _row_to_cuota(row, m)


@router.post("/{cuota_id:int}/abono-capital")
def registrar_abono_capital(cuota_id: int, payload: AbonoCapitalInput):
    f = payload.fecha or date.today().isoformat()
    with get_conn() as conn:
        if not (_table_exists(conn, "cuotas") and _table_exists(conn, "abonos_capital")):
            raise HTTPException(status_code=404, detail="Falta tabla 'cuotas' o 'abonos_capital'")
        m = _cuota_mapping(conn)
        row = conn.execute(
            f"SELECT {m['fk_prestamo']} AS id_prestamo, {m['nombre_cliente']} AS nombre_cliente FROM cuotas WHERE id=?;",
            (cuota_id,)
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Cuota no encontrada")
        id_prestamo = row["id_prestamo"]
        nombre_cliente = row["nombre_cliente"]
        ab_cols = _cols(conn, "abonos_capital")
        ab_fk = _pick(ab_cols, ["id_prestamo"]) or "id_prestamo"
        ab_nom = _pick(ab_cols, ["nombre_cliente"]) or "nombre_cliente"
        ab_fecha = _pick(ab_cols, ["fecha"]) or "fecha"
        ab_monto = _pick(ab_cols, ["monto"]) or "monto"
        conn.execute(
            f"INSERT INTO abonos_capital ({ab_fk},{ab_nom},{ab_fecha},{ab_monto}) VALUES (?,?,?,?);",
            (id_prestamo, nombre_cliente, f, float(payload.monto))
        )
        if m["abono_capital"]:
            conn.execute(
                f"UPDATE cuotas SET {m['abono_capital']} = COALESCE({m['abono_capital']}, 0) + ? WHERE id = ?;",
                (float(payload.monto), cuota_id)
            )
        conn.commit()
        try:
            csv_path = _db_dir(conn) / "abonos_capital_log.csv"
            write_header = not csv_path.exists()
            with open(csv_path, "a", newline="", encoding="utf-8") as fh:
                w = csv.writer(fh)
                if write_header:
                    w.writerow(["fecha", "id_prestamo", "nombre_cliente", "monto", "cuota_id"])
                w.writerow([f, id_prestamo, nombre_cliente or "", float(payload.monto), cuota_id])
        except Exception:
            pass
        return {"status": "ok", "id_prestamo": id_prestamo, "fecha": f, "monto": float(payload.monto)}

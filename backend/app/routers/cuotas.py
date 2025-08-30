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

# ---------- helper: row -> cuota dict ----------

def _row_to_cuota(row, m) -> Dict[str, Any]:
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

    # número de cuota (exponer ambos para compatibilidad: 'numero' y 'cuota_numero')
    num_val = fint(row[m["numero"]] if has(m["numero"]) else None)

    return {
        "id": row["id"],
        "id_prestamo": row[m["fk_prestamo"]] if has(m["fk_prestamo"]) else None,
        "cod_cli": row[m["cod_cli"]] if has(m["cod_cli"]) else None,
        "nombre_cliente": row[m["nombre_cliente"]] if has(m["nombre_cliente"]) else None,
        "modalidad": row[m["modalidad"]] if has(m["modalidad"]) else None,
        "numero": num_val,
        "cuota_numero": num_val,  # <-- clave legacy para la UI
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


# ---------- NUEVO: Resumen de préstamos (definido ANTES de rutas con {id}) ----------

@router.get("/resumen-prestamos")
def resumen_prestamos():
    """Resumen por préstamo (dinámico y tolerante a 'abonos_capital' ausente)."""
    hoy = date.today().isoformat()
    with get_conn() as conn:
        if not (_table_exists(conn, "prestamos") and _table_exists(conn, "cuotas")):
            return []

        m = _cuota_mapping(conn)
        cols_cuotas = _cols(conn, "cuotas")

        fk = m["fk_prestamo"]
        venc = m["venc"]
        interes_col = m["interes_a_pagar"]
        nombre_cli_col = m["nombre_cliente"] if m["nombre_cliente"] in cols_cuotas else None

        abonos_existe = _table_exists(conn, "abonos_capital")
        ab_sum_expr = (
            "COALESCE((SELECT SUM(a.monto) FROM abonos_capital a WHERE a.id_prestamo=p.id), 0)"
            if abonos_existe else "0"
        )
        total_interes_expr = f"COALESCE((SELECT SUM(c2.{interes_col}) FROM cuotas c2 WHERE c2.{fk}=p.id), 0)"
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
        ORDER BY p.id DESC
        """
        rows = conn.execute(sql, (hoy,)).fetchall()
        return [{k: r[k] for k in r.keys()} for r in rows]


@router.get("/prestamo/{prestamo_id:int}/resumen")
def resumen_de_prestamo(prestamo_id: int):
    """
    Resumen + lista de cuotas de un préstamo.
    - Calcula 'estado' con la misma regla del listado.
    - Calcula 'dias_mora' por cuota si está 'PENDIENTE'.
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

        hoy = date.today().isoformat()
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
        WHERE p.id = ?
        GROUP BY p.id
        """
        rr = conn.execute(res_sql, (hoy, prestamo_id)).fetchone()
        if not rr:
            raise HTTPException(status_code=404, detail="Préstamo no encontrado")

        resumen = {k: rr[k] for k in rr.keys()}

        cu_sql = f"SELECT * FROM cuotas WHERE {fk}=? ORDER BY {m['numero']};"
        cuotas = conn.execute(cu_sql, (prestamo_id,)).fetchall()
        cu_out: List[Dict[str, Any]] = []
        for c in cuotas:
            d = _row_to_cuota(c, m)
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
            # Fallback: si la cuota no trae modalidad, usa la del préstamo (resumen)
            if not d.get("modalidad"):
                try:
                    d["modalidad"] = resumen.get("modalidad")
                except Exception:
                    pass
            cu_out.append(d)

        return {"resumen": resumen, "cuotas": cu_out}

# ---------- Endpoints estándar (listar, obtener, pagar, abono) ----------

@router.get("")
@router.get("/", include_in_schema=False)
def listar_cuotas(cod_cli: Optional[str] = Query(default=None),
                  estado: Optional[str] = Query(default=None, regex=r"^(PENDIENTE|PAGADO)$"),
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
        sql += f" ORDER BY {m['fk_prestamo']} DESC, {m['numero']} ASC"
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
        try:
            prestamo_id = row[m["fk_prestamo"]]
            total = conn.execute(
                f"SELECT COUNT(*) AS c FROM cuotas WHERE {m['fk_prestamo']} = ?",
                (prestamo_id,)
            ).fetchone()[0]
            pagadas = conn.execute(
                f"SELECT COUNT(*) AS c FROM cuotas WHERE {m['fk_prestamo']} = ? AND UPPER({m['estado']}) = 'PAGADO'",
                (prestamo_id,)
            ).fetchone()[0]
            todas_pagadas = bool(total and pagadas == total)

            importe_credito_row = conn.execute("SELECT importe_credito FROM prestamos WHERE id = ?", (prestamo_id,)).fetchone()
            importe_credito = float(importe_credito_row["importe_credito"]) if importe_credito_row and "importe_credito" in importe_credito_row.keys() else 0.0

            capital_pagado = 0.0
            if _table_exists(conn, "abonos_capital"):
                r = conn.execute("SELECT COALESCE(SUM(monto),0) AS s FROM abonos_capital WHERE id_prestamo = ?", (prestamo_id,)).fetchone()
                capital_pagado = float(r["s"]) if r and "s" in r.keys() else 0.0
            else:
                if m.get("abono_capital") in _cols(conn, "cuotas"):
                    r = conn.execute(
                        f"SELECT COALESCE(SUM({m['abono_capital']}),0) AS s FROM cuotas WHERE {m['fk_prestamo']} = ?",
                        (prestamo_id,)
                    ).fetchone()
                    capital_pagado = float(r["s"]) if r and "s" in r.keys() else 0.0

            capital_cubierto = (importe_credito - capital_pagado) <= 1e-6

            if todas_pagadas and capital_cubierto:
                conn.execute("UPDATE prestamos SET estado = 'PAGADO' WHERE id = ?", (prestamo_id,))
        except Exception:
            pass
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

# ======================== RECORDATORIOS POR EMAIL =========================
# Endpoints NUEVOS y no invasivos:
#   - GET  /cuotas/recordatorios/preview?dias=1    (vista previa)
#   - POST /cuotas/recordatorios/enviar?dias=1     (envío real)
# Usa SMTP_* por variables de entorno (ya probaste el SMTP).

import os, smtplib
from email.message import EmailMessage
from datetime import timedelta

def _fmt_money(x) -> str:
    try:
        return f"${float(x):,.0f}"
    except Exception:
        return "$0"

def _smtp_cfg():
    return {
        "host": os.getenv("SMTP_HOST", ""),
        "port": int(os.getenv("SMTP_PORT", "587")),
        "user": os.getenv("SMTP_USER", ""),
        "pass": os.getenv("SMTP_PASS", ""),
        "from": os.getenv("SMTP_FROM", os.getenv("SMTP_USER", "no-reply@example.com")),
    }

def _send_email(to_addr: str, subject: str, body: str) -> (bool, str):
    cfg = _smtp_cfg()
    if not (cfg["host"] and cfg["from"] and to_addr):
        return False, "SMTP config incompleta o destinatario vacío"
    msg = EmailMessage()
    msg["From"] = cfg["from"]
    msg["To"] = to_addr
    msg["Subject"] = subject
    msg.set_content(body)
    try:
        with smtplib.SMTP(cfg["host"], cfg["port"], timeout=20) as s:
            try:
                s.starttls()
            except Exception:
                pass
            if cfg["user"]:
                s.login(cfg["user"], cfg["pass"])
            s.send_message(msg)
        return True, "enviado"
    except Exception as e:
        return False, str(e)

def _build_recordatorios(conn, dias: int) -> List[Dict[str, Any]]:
    """
    Arma recordatorios para cuotas PENDIENTES cuyo vencimiento = hoy + dias.
    Incluye: email, asunto, cuerpo, y datos de apoyo.
    """
    m = _cuota_mapping(conn)
    target = (date.today() + timedelta(days=int(dias))).isoformat()

    # ¿existe abonos_capital para calcular capital pendiente?
    abonos_existe = _table_exists(conn, "abonos_capital")

    sql = f"""
    SELECT
        c.*,
        p.id               AS p_id,
        p.importe_credito  AS p_importe,
        p.modalidad        AS p_modalidad,
        p.cod_cli          AS p_cod_cli,
        cl.id              AS cli_id,
        cl.nombre          AS cli_nombre,
        cl.email           AS cli_email
    FROM cuotas c
    JOIN prestamos p ON c.{m['fk_prestamo']} = p.id
    LEFT JOIN clientes cl ON cl.codigo = p.cod_cli
    WHERE UPPER(c.{m['estado']}) = 'PENDIENTE'
      AND date(c.{m['venc']}) = date(?)
    ORDER BY p.id, c.{m['numero']}
    """

    rows = conn.execute(sql, (target,)).fetchall()
    out: List[Dict[str, Any]] = []

    for r in rows:
        # Valor de la cuota (usamos el campo de interés/importe registrado en cuotas)
        valor = r[m["interes_a_pagar"]] if m["interes_a_pagar"] in r.keys() else None

        # Capital pendiente del préstamo
        p_id = r["p_id"]
        importe = float(r["p_importe"] or 0)
        capital_pagado = 0.0
        if abonos_existe:
            rr = conn.execute("SELECT COALESCE(SUM(monto),0) AS s FROM abonos_capital WHERE id_prestamo = ?", (p_id,)).fetchone()
            capital_pagado = float(rr["s"] if rr and "s" in rr.keys() else 0.0)
        cap_pend = max(importe - capital_pagado, 0)

        numero = r[m["numero"]] if m["numero"] in r.keys() else None
        fv = r[m["venc"]] if m["venc"] in r.keys() else target
        modalidad = r["p_modalidad"]

        nombre = r["cli_nombre"] or "(sin nombre)"
        email_to = (r["cli_email"] or "").strip()

        # Texto "vence mañana" si dias=1; si no, fecha explícita
        vence_txt = "mañana" if int(dias) == 1 else f"el {target}"

        # Mensaje
        subject = f"Recordatorio: cuota #{numero} vence {vence_txt}"
        body = (
            f"Hola {nombre},\n\n"
            f"Le recordamos que su cuota #{numero} ({modalidad}) de fecha {fv} por valor de {_fmt_money(valor)} "
            f"vence {vence_txt}.\n"
            f"Capital pendiente: {_fmt_money(cap_pend)}.\n\n"
            f"Si ya realizó el pago, por favor ignore este mensaje.\n\n"
            f"Gracias."
        )

        out.append({
            "prestamo_id": p_id,
            "cuota_id": r["id"],
            "cliente_id": r["cli_id"],
            "cliente_nombre": nombre,
            "email_to": email_to,
            "asunto": subject,
            "mensaje": body,
            "fecha_vencimiento": fv,
            "valor_cuota": float(valor or 0),
            "capital_pendiente": float(cap_pend),
            "dias": int(dias),
        })

    return out

@router.get("/recordatorios/preview")
def preview_recordatorios(dias: int = Query(1, ge=0, le=30), incluir_sin_email: bool = Query(False)):
    """
    Vista previa (no envía). Útil para revisar antes de notificar.
    - dias: 1 => mañana; 0 => hoy; N => en N días.
    - incluir_sin_email: si True, incluye clientes sin email para depurar.
    """
    with get_conn() as conn:
        if not (_table_exists(conn, "cuotas") and _table_exists(conn, "prestamos") and _table_exists(conn, "clientes")):
            return []
        items = _build_recordatorios(conn, dias)
        if not incluir_sin_email:
            items = [x for x in items if x["email_to"]]
        return items

@router.post("/recordatorios/enviar")
def enviar_recordatorios(dias: int = Query(1, ge=0, le=30), dry_run: bool = Query(False)):
    """
    Envía emails de recordatorio para cuotas que vencen en 'dias'.
    - dry_run=True: no envía, solo retorna lo que enviaría.
    Respuesta: conteos, errores y items procesados.
    """
    with get_conn() as conn:
        if not (_table_exists(conn, "cuotas") and _table_exists(conn, "prestamos") and _table_exists(conn, "clientes")):
            raise HTTPException(status_code=404, detail="Faltan tablas requeridas")
        items = _build_recordatorios(conn, dias)

    # Filtra solo los que tienen email
    to_send = [x for x in items if x["email_to"]]
    sent, errors = 0, []

    if not dry_run:
        for it in to_send:
            ok, msg = _send_email(it["email_to"], it["asunto"], it["mensaje"])
            if ok:
                sent += 1
            else:
                errors.append({"cuota_id": it["cuota_id"], "email_to": it["email_to"], "error": msg})

    return {
        "total_detectados": len(items),
        "con_email": len(to_send),
        "enviados": sent if not dry_run else 0,
        "dry_run": dry_run,
        "errores": errors,
        "items": items if dry_run else to_send
    }
# =======================================================================

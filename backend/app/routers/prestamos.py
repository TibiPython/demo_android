# backend/app/routers/prestamos.py
from __future__ import annotations

import os
import sqlite3
from datetime import date, datetime, timedelta
from typing import Any, Dict, List, Literal, Optional

from fastapi import APIRouter, BackgroundTasks, HTTPException, Query
from pydantic import AliasChoices, BaseModel, Field, ValidationInfo, field_validator

from app.deps import get_conn

# Envío de correo (si no existe el módulo, se hace no-op para no romper)
try:
    from app.notifications import send_loan_created_email
except Exception:  # pragma: no cover
    def send_loan_created_email(*args, **kwargs):  # type: ignore
        return None

router = APIRouter()

# -------------------------------------------------------------
# Utilidades de esquema
# -------------------------------------------------------------
def _table_exists(conn, name: str) -> bool:
    row = conn.execute(
        "SELECT COUNT(*) AS c FROM sqlite_master WHERE type='table' AND name=?;",
        (name,),
    ).fetchone()
    return bool(row and int(row["c"] or 0))

def _cols(conn, table: str) -> List[str]:
    try:
        return [r["name"] for r in conn.execute(f"PRAGMA table_info({table});").fetchall()]
    except Exception:
        return []

def _pick(options: List[str], cols: List[str]) -> Optional[str]:
    for o in options:
        if o in cols:
            return o
    return None

# -------------------------------------------------------------
# Guardrail de correo (helper)
# -------------------------------------------------------------
def _mail_can_send_on_create(conn, prestamo_id: int):
    """
    Verifica si hay condiciones mínimas para enviar correo al crear el préstamo.
    Devuelve (ok: bool, motivo: str, email: Optional[str]).
    """
    try:
        if not (_table_exists(conn, "prestamos") and _table_exists(conn, "clientes")):
            return (False, "Falta tabla 'prestamos' o 'clientes'", None)

        p = conn.execute(
            "SELECT id, cod_cli FROM prestamos WHERE id=?;",
            (prestamo_id,),
        ).fetchone()
        if not p:
            return (False, f"Prestamo {prestamo_id} no encontrado", None)

        cod_cli = (p["cod_cli"] or "").strip()
        if not cod_cli:
            return (False, f"Prestamo {prestamo_id} sin cod_cli", None)

        cols_cli = _cols(conn, "clientes")
        email_col = _pick(["email", "correo", "mail", "e_mail"], cols_cli)
        if not email_col:
            return (False, "No existe columna de email en 'clientes'", None)

        id_cli_col = _pick(
            ["cod_cli", "codigo", "cod_cliente", "codcliente", "id", "id_cliente", "cliente_id"],
            cols_cli,
        )
        if not id_cli_col:
            return (False, "No existe columna identificadora del cliente en 'clientes'", None)

        row_cli = conn.execute(
            f"SELECT {email_col} AS email FROM clientes WHERE {id_cli_col}=?;",
            (cod_cli,),
        ).fetchone()
        email = (row_cli["email"] or "").strip() if row_cli and "email" in row_cli.keys() else ""

        if not email or "@" not in email or "." not in email.split("@")[-1]:
            return (False, f"Email inválido o vacío para cod_cli={cod_cli}", None)

        return (True, "OK", email)
    except Exception as e:
        return (False, f"Excepción validando correo: {e}", None)

# -------------------------------------------------------------
# Modelos
# -------------------------------------------------------------
class _CuotaPlanIn(BaseModel):
    capital: float = Field(ge=0)
    interes: float = Field(ge=0)

class PrestamoAutoIn(BaseModel):
    cod_cli: str = Field(min_length=1, validation_alias=AliasChoices("cod_cli", "codigo"))
    monto: float = Field(gt=0, validation_alias=AliasChoices("monto", "importe_credito"))
    tasa_interes: float = Field(ge=0, validation_alias=AliasChoices("tasa_interes", "tasa"))
    modalidad: Literal["Mensual", "Quincenal"]
    num_cuotas: int = Field(gt=0, validation_alias=AliasChoices("num_cuotas", "numero_cuotas"))
    fecha_inicio: date = Field(validation_alias=AliasChoices("fecha_inicio", "fecha_credito"))

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

class PrestamoManualIn(PrestamoAutoIn):
    tasa: float = Field(ge=0)  # en manual recibes "tasa"
    plan: List[_CuotaPlanIn]

    @field_validator("plan")
    @classmethod
    def _check_plan_len(cls, v, info: ValidationInfo):
        n = None
        try:
            n = info.data.get("num_cuotas") if isinstance(info.data, dict) else None
        except Exception:
            n = None
        if n and len(v) != n:
            raise ValueError(f"El plan debe tener exactamente {n} cuotas")
        return v

class PrestamoAutoUpdateIn(BaseModel):
    cod_cli: str = Field(min_length=1, validation_alias=AliasChoices("cod_cli", "codigo"))
    monto: float = Field(gt=0, validation_alias=AliasChoices("monto", "importe_credito"))
    tasa_interes: float = Field(ge=0, validation_alias=AliasChoices("tasa_interes", "tasa"))
    modalidad: Literal["Mensual", "Quincenal"]
    num_cuotas: int = Field(gt=0, validation_alias=AliasChoices("num_cuotas", "numero_cuotas"))
    fecha_inicio: date = Field(validation_alias=AliasChoices("fecha_inicio", "fecha_credito"))

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

class PrestamoReplanIn(BaseModel):
    modalidad: Optional[Literal["Mensual", "Quincenal"]] = None
    plan: List[_CuotaPlanIn]

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

# -------------------------------------------------------------
# Ayudas de negocio / esquema
# -------------------------------------------------------------
def _calc_due(fecha_inicio: date, modalidad: str, n: int) -> date:
    """Primera cuota a +1 período desde fecha_inicio. Mensual:+n meses; Quincenal:+14*n días."""
    if modalidad.strip().lower().startswith("quin"):
        return fecha_inicio + timedelta(days=14 * int(n))

    base = datetime.fromisoformat(fecha_inicio.isoformat())
    n = int(n)
    m = base.month - 1 + n
    y = base.year + m // 12
    m = m % 12 + 1
    day = min(
        base.day,
        [31, 29 if y % 4 == 0 and (y % 100 != 0 or y % 400 == 0) else 28,
         31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1],
    )
    return date(y, m, day)

def _calc_due_guarded(fecha_inicio: date, modalidad: str, n: int) -> date:
    n = max(1, int(n or 1))
    due = _calc_due(fecha_inicio, modalidad, n)
    if due <= fecha_inicio:
        due = _calc_due(fecha_inicio, modalidad, n + 1)
    return due

def _ensure_plan_columns(conn):
    # prestamos.plan_mode
    if _table_exists(conn, "prestamos"):
        cols = _cols(conn, "prestamos")
        if "plan_mode" not in cols:
            try:
                conn.execute("ALTER TABLE prestamos ADD COLUMN plan_mode TEXT DEFAULT 'auto';")
                conn.commit()
            except Exception:
                pass

    # cuotas columnas plan
    if _table_exists(conn, "cuotas"):
        cols_q = _cols(conn, "cuotas")
        changed = False
        for colname, coltype in [
            ("capital_plan", "REAL NOT NULL DEFAULT 0"),
            ("interes_plan", "REAL NOT NULL DEFAULT 0"),
            ("total_plan", "REAL NOT NULL DEFAULT 0"),
        ]:
            if colname not in cols_q:
                try:
                    conn.execute(f"ALTER TABLE cuotas ADD COLUMN {colname} {coltype};")
                    changed = True
                except Exception:
                    pass
        if changed:
            try:
                conn.commit()
            except Exception:
                pass

def _prestamo_to_front(conn, p_row) -> Dict[str, Any]:
    out = {
        "id": p_row["id"],
        "cod_cli": p_row["cod_cli"],
        "fecha_credito": p_row["fecha_credito"],
        "importe_credito": p_row["importe_credito"],
        "modalidad": p_row["modalidad"],
        "tasa_interes": p_row["tasa_interes"],
        "estado": p_row["estado"] if "estado" in p_row.keys()
        else (p_row["estado_capital"] if "estado_capital" in p_row.keys() else "PENDIENTE"),
    }
    c = conn.execute(
        "SELECT id, codigo, nombre FROM clientes WHERE codigo=?;",
        (p_row["cod_cli"],),
    ).fetchone()
    if c:
        out["cliente"] = {"id": c["id"], "codigo": c["codigo"], "nombre": c["nombre"]}
    return out

def _estado_prestamo_dinamico(conn, prestamo_id: int) -> str:
    if not _table_exists(conn, "cuotas"):
        return "PENDIENTE"
    cols = set(_cols(conn, "cuotas"))
    fk = _pick(["id_prestamo", "prestamo_id"], list(cols)) or "id_prestamo"
    fecha_col = _pick(["fecha_vencimiento", "fecha"], list(cols))
    has_ipg = "interes_pagado" in cols
    has_abcap = "abono_capital" in cols
    has_estado = "estado" in cols

    cuotas = conn.execute(f"SELECT * FROM cuotas WHERE {fk}=?;", (prestamo_id,)).fetchall()
    if not cuotas:
        return "PENDIENTE"

    total = len(cuotas)
    pagadas = 0
    hoy = date.today()
    vencida_pendiente = False

    for r in cuotas:
        estado_c = (r["estado"] if has_estado else "PENDIENTE") or "PENDIENTE"
        ipg = float(r["interes_pagado"]) if has_ipg and r["interes_pagado"] is not None else 0.0
        abcap = float(r["abono_capital"]) if has_abcap and r["abono_capital"] is not None else 0.0
        if estado_c == "PAGADO" or ipg > 0 or abcap > 0:
            pagadas += 1
        else:
            if fecha_col and r[fecha_col]:
                try:
                    f = date.fromisoformat(str(r[fecha_col]))
                    if f < hoy:
                        vencida_pendiente = True
                except Exception:
                    pass

    if pagadas >= total:
        return "PAGADO"
    if vencida_pendiente:
        return "VENCIDO"
    return "PENDIENTE"

def _validar_plan_manual_o_400(monto: float, tasa: float, plan: List[Dict[str, Any]]) -> None:
    tol = 0.01
    if monto <= 0:
        raise HTTPException(status_code=400, detail="Monto debe ser > 0")
    if tasa < 0:
        raise HTTPException(status_code=400, detail="Tasa no puede ser negativa")
    if not plan or not isinstance(plan, list):
        raise HTTPException(status_code=400, detail="El plan es obligatorio")

    saldo = float(monto)
    suma_cap = 0.0
    for idx, cuota in enumerate(plan, start=1):
        try:
            cap = float(cuota.get("capital", 0))
            inte = float(cuota.get("interes", 0))
        except Exception:
            raise HTTPException(status_code=400, detail=f"Cuota {idx}: capital/interés no numérico")
        if cap < -tol or inte < -tol:
            raise HTTPException(status_code=400, detail=f"Cuota {idx}: capital/interés no pueden ser negativos")
        interes_esp = round((monto if idx == 1 else saldo) * float(tasa) / 100.0, 2)
        if abs(inte - interes_esp) > tol:
            raise HTTPException(
                status_code=400,
                detail=f"Cuota {idx}: el interés ({inte:.2f}) no coincide con el calculado ({interes_esp:.2f})",
            )
        saldo = round(saldo - cap, 2)
        if saldo < -tol:
            raise HTTPException(status_code=400, detail=f"Cuota {idx}: el capital deja saldo negativo ({saldo:.2f})")
        suma_cap = round(suma_cap + cap, 2)

    if abs(suma_cap - float(monto)) > tol:
        raise HTTPException(
            status_code=400,
            detail=f"La suma de capital del plan ({suma_cap:.2f}) debe igualar el monto ({monto:.2f})",
        )
    if abs(saldo) > tol:
        raise HTTPException(status_code=400, detail=f"Saldo de capital final distinto de 0 ({saldo:.2f})")

def _insert_cuota_flexible(conn, prestamo_id: int, i: int, fv_iso: str, c_capital: float, c_interes: float):
    if not _table_exists(conn, "cuotas"):
        raise HTTPException(status_code=500, detail="No existe tabla 'cuotas'")

    cols = _cols(conn, "cuotas")
    fk = _pick(["id_prestamo", "prestamo_id"], cols) or "id_prestamo"
    num_col = _pick(["cuota_numero", "numero"], cols)
    fecha_col = _pick(["fecha_vencimiento", "fecha"], cols)

    fields: List[str] = [fk]
    values: List[Any] = [prestamo_id]
    if num_col:
        fields.append(num_col); values.append(i)
    if fecha_col:
        fields.append(fecha_col); values.append(fv_iso)

    has_estado = "estado" in cols
    has_ipg = "interes_pagado" in cols
    has_abcap = "abono_capital" in cols
    has_iap = "interes_a_pagar" in cols or "interes" in cols
    iap_col = _pick(["interes_a_pagar", "interes"], cols)
    has_capital = "capital" in cols
    has_total = "total" in cols
    has_cap_plan = "capital_plan" in cols
    has_int_plan = "interes_plan" in cols
    has_tot_plan = "total_plan" in cols

    if has_estado:
        fields.append("estado"); values.append("PENDIENTE")
    if has_ipg:
        fields.append("interes_pagado"); values.append(0.0)
    if has_abcap:
        fields.append("abono_capital"); values.append(0.0)

    if has_cap_plan:
        fields.append("capital_plan"); values.append(float(c_capital))
    if has_int_plan:
        fields.append("interes_plan"); values.append(float(c_interes))
    if has_tot_plan:
        fields.append("total_plan"); values.append(round(float(c_capital) + float(c_interes), 2))

    if has_capital:
        fields.append("capital"); values.append(float(c_capital))
    if has_total:
        fields.append("total"); values.append(round(float(c_capital) + float(c_interes), 2))
    if has_iap and iap_col:
        fields.append(iap_col); values.append(float(c_interes))

    placeholders = ", ".join(["?"] * len(values))
    sql = f"INSERT INTO cuotas ({', '.join(fields)}) VALUES ({placeholders});"
    try:
        conn.execute(sql, values)
    except sqlite3.Error as e:
        raise HTTPException(status_code=400, detail=f"Error al insertar cuota {i}: {e}")

# -------------------------------------------------------------
# ENDPOINTS
# -------------------------------------------------------------

# POST CREAR PRESTAMO AUTO
@router.post("")
def crear_prestamo_auto(data: PrestamoAutoIn, bg: BackgroundTasks):
    with get_conn() as conn:
        if not _table_exists(conn, "prestamos"):
            raise HTTPException(status_code=500, detail="No existe tabla 'prestamos'")
        _ensure_plan_columns(conn)

        try:
            cur = conn.execute(
                "INSERT INTO prestamos (cod_cli, fecha_credito, importe_credito, modalidad, tasa_interes, num_cuotas, plan_mode)"
                " VALUES (?, ?, ?, ?, ?, ?, 'auto');",
                (
                    data.cod_cli,
                    data.fecha_inicio.isoformat(),
                    float(data.monto),
                    data.modalidad,
                    float(data.tasa_interes),
                    int(data.num_cuotas),
                ),
            )
            prestamo_id = int(cur.lastrowid)

            if not _table_exists(conn, "cuotas"):
                raise HTTPException(status_code=500, detail="No existe tabla 'cuotas'")

            for i in range(1, data.num_cuotas + 1):
                fv = _calc_due_guarded(data.fecha_inicio, data.modalidad, i).isoformat()
                interes = round(float(data.monto) * float(data.tasa_interes) / 100.0, 2)
                _insert_cuota_flexible(conn, prestamo_id, i, fv, 0.0, interes)

            conn.commit()
        except sqlite3.Error as e:
            raise HTTPException(status_code=400, detail=f"Error SQL al crear préstamo: {e}")
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(status_code=400, detail=f"Error inesperado al crear préstamo: {type(e).__name__}: {e}")

        # Respuesta al front
        res = _prestamo_to_front(conn, conn.execute("SELECT * FROM prestamos WHERE id=?", (prestamo_id,)).fetchone())

         # MAIL GUARDRAIL (INLINE)
        def _pick_first(candidates: List[str], cols: List[str]) -> Optional[str]:
            for c in candidates:
                if c in cols:
                    return c
            return None

        send_on = (os.getenv("MAIL_SEND_ON_CREATE", "on") or "").strip().lower() in {"1", "true", "on", "yes", "y"}
        ok_send, motivo_send, email_to = False, "", None

        if send_on:
            cod_cli = (res.get("cod_cli") or "").strip()
            if not cod_cli:
                motivo_send = "Prestamo sin cod_cli"
            elif not _table_exists(conn, "clientes"):
                motivo_send = "Falta tabla clientes"
            else:
                cols_cli = _cols(conn, "clientes")
                email_col = _pick_first(["email", "correo", "mail", "e_mail"], cols_cli)
                if not email_col:
                    motivo_send = "No existe columna de email en 'clientes'"
                else:
                    id_cli_col = _pick_first(
                        ["cod_cli", "codigo", "cod_cliente", "codcliente", "id", "id_cliente", "cliente_id"],
                        cols_cli,
                    )
                    if not id_cli_col:
                        motivo_send = "No existe columna identificadora del cliente en 'clientes'"
                    else:
                        row_cli = conn.execute(
                            f"SELECT {email_col} AS email FROM clientes WHERE {id_cli_col}=?;",
                            (cod_cli,),
                        ).fetchone()
                        email = (row_cli["email"] or "").strip() if row_cli and "email" in row_cli.keys() else ""
                        if email and "@" in email and "." in email.split("@")[-1]:
                            ok_send, email_to = True, email
                        else:
                            motivo_send = f"Email inválido o vacío para cod_cli={cod_cli}"

        # Envío (simple: notifications.py decide el contenido del email)
        if send_on and ok_send:
            try:
                bg.add_task(send_loan_created_email, res["id"])  # se envía solo con id
            except Exception as e:
                print(f"WARNING: Envío de correo fallido (prestamo_id={res.get('id')}): {e}")
        else:
            print(f"INFO: Correo NO enviado (prestamo_id={res.get('id')}). Motivo='{motivo_send}'. Flag={send_on}")

        return res

# POST CREAR PRESTAMO MANUAL
@router.post("/manual")
def crear_prestamo_manual(data: PrestamoManualIn, bg: BackgroundTasks):
    with get_conn() as conn:
        if not _table_exists(conn, "prestamos"):
            raise HTTPException(status_code=500, detail="No existe tabla 'prestamos'")

        plan_payload = [{"capital": p.capital, "interes": p.interes} for p in data.plan]
        _validar_plan_manual_o_400(float(data.monto), float(data.tasa), plan_payload)
        _ensure_plan_columns(conn)

        try:
            cur = conn.execute(
                "INSERT INTO prestamos (cod_cli, fecha_credito, importe_credito, modalidad, tasa_interes, num_cuotas, plan_mode)"
                " VALUES (?, ?, ?, ?, ?, ?, 'manual');",
                (
                    data.cod_cli,
                    data.fecha_inicio.isoformat(),
                    float(data.monto),
                    data.modalidad,
                    float(data.tasa),
                    int(data.num_cuotas),
                ),
            )
            prestamo_id = int(cur.lastrowid)

            if not _table_exists(conn, "cuotas"):
                raise HTTPException(status_code=500, detail="No existe tabla 'cuotas'")

            for i, c in enumerate(data.plan, start=1):
                fv = _calc_due_guarded(data.fecha_inicio, data.modalidad, i).isoformat()
                _insert_cuota_flexible(conn, prestamo_id, i, fv, float(c.capital), float(c.interes))

            conn.commit()
        except sqlite3.Error as e:
            raise HTTPException(status_code=400, detail=f"Error SQL al crear préstamo manual: {e}")
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(status_code=400, detail=f"Error inesperado al crear préstamo manual: {type(e).__name__}: {e}")

        row = conn.execute("SELECT * FROM prestamos WHERE id=?", (prestamo_id,)).fetchone()
        res = _prestamo_to_front(conn, row)
        try:
            bg.add_task(send_loan_created_email, res["id"])  # type: ignore[arg-type]
        except Exception:
            pass
        return res

# GET ESTADO LOTE
@router.get("/estado-lote", summary="Listar estado canónico de préstamos (por lote)")
def listar_estado_prestamos(ids: Optional[str] = Query(default=None)):
    if not ids:
        return []
    try:
        id_list = [int(x.strip()) for x in ids.split(",") if x.strip()]
    except ValueError:
        raise HTTPException(status_code=400, detail="Formato de 'ids' inválido")

    out: List[Dict[str, Any]] = []
    with get_conn() as conn:
        for pid in id_list:
            try:
                out.append(_estado_prestamo_canonico(conn, pid))
            except HTTPException as e:
                out.append({"id": pid, "error": e.detail})
    return out

# GET PLAN (solo lectura, con ajuste dinámico opcional)
@router.get("/{prestamo_id:int}/plan", summary="Obtener plan de cuotas del préstamo")
def obtener_plan_prestamo(prestamo_id: int):
    import os as _os
    with get_conn() as conn:
        if not _table_exists(conn, "prestamos"):
            raise HTTPException(status_code=500, detail="No existe tabla 'prestamos'")
        p = conn.execute("SELECT * FROM prestamos WHERE id=?", (prestamo_id,)).fetchone()
        if not p:
            raise HTTPException(status_code=404, detail="Préstamo no encontrado")

        out = {
            "id": p["id"],
            "cod_cli": p["cod_cli"],
            "monto": float(p["importe_credito"]),
            "modalidad": p["modalidad"],
            "fecha_inicio": p["fecha_credito"],
            "num_cuotas": int(p["num_cuotas"]),
            "tasa": float(p["tasa_interes"]),
            "plan_mode": p["plan_mode"] if "plan_mode" in p.keys() else "auto",
            "estado": p["estado"] if "estado" in p.keys()
                      else (p["estado_capital"] if "estado_capital" in p.keys() else "PENDIENTE"),
            "plan": [],
            "last_paid_num": 0,
        }

        try:
            out["estado"] = _estado_prestamo_dinamico(conn, int(prestamo_id))
        except Exception:
            pass

        if not _table_exists(conn, "cuotas"):
            return out

        cols = _cols(conn, "cuotas")
        fk = _pick(["id_prestamo", "prestamo_id"], cols) or "id_prestamo"
        num_col = _pick(["cuota_numero", "numero"], cols) or "cuota_numero"
        fecha_col = _pick(["fecha_vencimiento", "fecha"], cols) or "fecha_vencimiento"
        cap_src = _pick(["capital_plan", "capital"], cols)
        int_src = _pick(["interes_plan", "interes_a_pagar", "interes"], cols)
        has_ipg = "interes_pagado" in cols
        has_abcap = "abono_capital" in cols
        has_estado = "estado" in cols

        rows = conn.execute(f"SELECT * FROM cuotas WHERE {fk}=? ORDER BY {num_col} ASC;", (prestamo_id,)).fetchall()

        last_paid = 0
        for r in rows:
            numero = int(r[num_col])
            estado_c = (r["estado"] if has_estado else "PENDIENTE") or "PENDIENTE"
            ipg = float(r["interes_pagado"]) if has_ipg and r["interes_pagado"] is not None else 0.0
            abcap = float(r["abono_capital"]) if has_abcap and r["abono_capital"] is not None else 0.0
            if estado_c == "PAGADO" or ipg > 0 or abcap > 0:
                if numero > last_paid:
                    last_paid = numero
            c = float(r[cap_src]) if cap_src else 0.0
            i = float(r[int_src]) if int_src else 0.0
            out["plan"].append(
                {
                    "numero": numero,
                    "fecha": r[fecha_col],
                    "capital": c,
                    "interes": i,
                    "estado": estado_c,
                    "interes_pagado": ipg,
                    "abono_capital": abcap,
                    "editable": numero > last_paid,
                }
            )

        # Ajuste dinámico de interés para la próxima cuota (SOLO LECTURA)
        try:
            flag = (_os.getenv("AUTO_INTERES_ABONOS", "") or "").strip().lower() in {"1", "true", "on", "yes", "y"}
            if flag and (out.get("plan_mode") == "auto") and (last_paid < int(out.get("num_cuotas", 0))):
                next_num = last_paid + 1
                abonos_sum = 0.0
                if has_abcap:
                    row_ab = conn.execute(
                        f"SELECT COALESCE(SUM(COALESCE(abono_capital,0)),0) AS s "
                        f"FROM cuotas WHERE {fk}=? AND {num_col}<=?;",
                        (prestamo_id, next_num),
                    ).fetchone()
                    abonos_sum = float(row_ab["s"] or 0.0) if row_ab and "s" in row_ab.keys() else 0.0

                cap_pend = max(0.0, float(out.get("monto", 0)) - abonos_sum)
                tasa = float(out.get("tasa", 0))
                interes_next = round(cap_pend * tasa / 100.0, 2)

                for it in out["plan"]:
                    if int(it.get("numero", 0)) == next_num:
                        it["interes"] = interes_next
                        break
        except Exception:
            pass

        out["last_paid_num"] = last_paid
        return out

# PUT PRESTAMO AUTO (quirúrgico)
@router.put("/{prestamo_id:int}")
def actualizar_prestamo_auto(prestamo_id: int, data: PrestamoAutoUpdateIn):
    def _add_months(d: date, n: int) -> date:
        y = d.year + (d.month - 1 + n) // 12
        m = (d.month - 1 + n) % 12 + 1
        day = min(d.day, [31, 29 if (y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)) else 28,
                          31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1])
        return date(y, m, day)

    with get_conn() as conn:
        p = conn.execute("SELECT * FROM prestamos WHERE id=?", (prestamo_id,)).fetchone()
        if not p:
            raise HTTPException(status_code=404, detail="Préstamo no encontrado")

        plan_mode = p["plan_mode"] if "plan_mode" in p.keys() else "auto"
        if plan_mode == "manual":
            raise HTTPException(status_code=400, detail="Este préstamo es manual; usa PUT /prestamos/{id}/replan")

        monto = float(p["importe_credito"])
        tasa = float(p["tasa_interes"])
        modalidad = p["modalidad"] or "Mensual"
        fecha_inicio = p["fecha_credito"]
        if isinstance(fecha_inicio, str):
            try:
                yyyy, mm, dd = map(int, fecha_inicio.split("-"))
                fecha_inicio = date(yyyy, mm, dd)
            except Exception:
                raise HTTPException(status_code=400, detail="fecha_credito inválida en préstamo")

        num_actual = int(p["num_cuotas"])
        num_nuevo = int(data.num_cuotas) if getattr(data, "num_cuotas", None) is not None else num_actual

        cols = _cols(conn, "cuotas")
        fk = _pick(["id_prestamo", "prestamo_id"], cols) or "id_prestamo"
        num_col = _pick(["cuota_numero", "numero"], cols) or "cuota_numero"
        has_estado = "estado" in cols
        has_ipg = "interes_pagado" in cols
        has_abcap = "abono_capital" in cols

        rows = conn.execute(f"SELECT * FROM cuotas WHERE {fk}=? ORDER BY {num_col} ASC;", (prestamo_id,)).fetchall()
        last_paid = 0
        for r in rows:
            estado_c = (r["estado"] if has_estado else "PENDIENTE") or "PENDIENTE"
            ipg = float(r["interes_pagado"]) if has_ipg and r["interes_pagado"] is not None else 0.0
            abcap = float(r["abono_capital"]) if has_abcap and r["abono_capital"] is not None else 0.0
            if estado_c == "PAGADO" or ipg > 0 or abcap > 0:
                n = int(r[num_col])
                if n > last_paid:
                    last_paid = n

        if num_nuevo < last_paid:
            raise HTTPException(
                status_code=422,
                detail=f"No se puede reducir num_cuotas por debajo de las cuotas ya pagadas (última pagada: {last_paid}).",
            )

        to_set: Dict[str, Any] = {}
        if getattr(data, "tasa_interes", None) is not None:
            to_set["tasa_interes"] = float(data.tasa_interes)
            tasa = float(data.tasa_interes)
        if getattr(data, "modalidad", None) is not None:
            to_set["modalidad"] = str(data.modalidad)
            modalidad = str(data.modalidad)
        if getattr(data, "fecha_inicio", None) is not None:
            try:
                yyyy, mm, dd = map(int, str(data.fecha_inicio).split("-"))
                fecha_inicio = date(yyyy, mm, dd)
                to_set["fecha_credito"] = str(data.fecha_inicio)
            except Exception:
                raise HTTPException(status_code=422, detail="fecha_inicio inválida")
        if getattr(data, "num_cuotas", None) is not None:
            to_set["num_cuotas"] = int(data.num_cuotas)

        if to_set:
            set_clause = ", ".join([f"{k}=?" for k in to_set.keys()])
            params = list(to_set.values()) + [prestamo_id]
            conn.execute(f"UPDATE prestamos SET {set_clause} WHERE id=?", params)

        next_num = last_paid + 1
        if num_nuevo >= next_num:
            conn.execute(f"DELETE FROM cuotas WHERE {fk}=? AND {num_col}>=?;", (prestamo_id, next_num))
            interes_por_cuota = round(monto * tasa / 100.0, 2)
            for n in range(next_num, num_nuevo + 1):
                if modalidad.lower().startswith("mens"):
                    fv = _add_months(fecha_inicio, n)
                else:
                    fv = fecha_inicio + timedelta(days=15 * n)
                _insert_cuota_flexible(conn, prestamo_id, n, fv.isoformat(), 0.0, interes_por_cuota)

        conn.commit()

        row = conn.execute("SELECT * FROM prestamos WHERE id=?", (prestamo_id,)).fetchone()
        out = _prestamo_to_front(conn, row)
        try:
            out["estado"] = _estado_prestamo_dinamico(conn, int(prestamo_id))
        except Exception:
            pass
        out["last_paid_num"] = last_paid
        return out

# PUT REPLAN (manual)
@router.put("/{prestamo_id:int}/replan")
def replan_prestamo(prestamo_id: int, data: PrestamoReplanIn):
    tol = 0.01
    with get_conn() as conn:
        if not _table_exists(conn, "prestamos"):
            raise HTTPException(status_code=500, detail="No existe tabla 'prestamos'")
        p = conn.execute("SELECT * FROM prestamos WHERE id=?", (prestamo_id,)).fetchone()
        if not p:
            raise HTTPException(status_code=404, detail="Préstamo no encontrado")

        plan_mode = p["plan_mode"] if "plan_mode" in p.keys() else "auto"
        estado = p["estado"] if "estado" in p.keys() else (p["estado_capital"] if "estado_capital" in p.keys() else "PENDIENTE")
        if plan_mode != "manual":
            raise HTTPException(status_code=400, detail="Este préstamo no es de modo manual")
        if estado == "PAGADO":
            raise HTTPException(status_code=400, detail="No se puede editar un préstamo ya pagado")

        if _table_exists(conn, "cuotas"):
            cols0 = _cols(conn, "cuotas")
            fk0 = _pick(["id_prestamo", "prestamo_id"], cols0) or "id_prestamo"
            q = conn.execute(
                f"SELECT COUNT(*) AS c FROM cuotas WHERE {fk0}=? AND "
                f"(COALESCE(interes_pagado,0)>0 OR COALESCE(abono_capital,0)>0);",
                (prestamo_id,),
            ).fetchone()
            if int(q["c"] or 0) > 0:
                raise HTTPException(status_code=400, detail="No se puede editar: hay cuotas con pagos registrados")

        monto_total = float(p["importe_credito"])
        abonos_registrados = 0.0
        if _table_exists(conn, "cuotas"):
            cols1 = _cols(conn, "cuotas")
            fk1 = _pick(["id_prestamo", "prestamo_id"], cols1) or "id_prestamo"
            abonos_registrados = float(
                conn.execute(
                    f"SELECT COALESCE(SUM(COALESCE(abono_capital,0)),0) AS s FROM cuotas WHERE {fk1}=?;",
                    (prestamo_id,),
                ).fetchone()["s"]
            ) or 0.0

        plan_capital = round(sum(float(x.capital) for x in data.plan), 2)
        pendiente = round(monto_total - abonos_registrados, 2)
        if abs(plan_capital - pendiente) > tol:
            raise HTTPException(
                status_code=400,
                detail=f"La suma de capital del nuevo plan ({plan_capital:.2f}) debe igualar el capital pendiente ({pendiente:.2f})",
            )

        _ensure_plan_columns(conn)

        try:
            if not _table_exists(conn, "cuotas"):
                raise HTTPException(status_code=500, detail="No existe tabla 'cuotas'")

            cols = _cols(conn, "cuotas")
            fk = _pick(["id_prestamo", "prestamo_id"], cols) or "id_prestamo"
            num_col = _pick(["cuota_numero", "numero"], cols) or "cuota_numero"
            fecha_col = _pick(["fecha_vencimiento", "fecha"], cols) or "fecha_vencimiento"

            rows = conn.execute(f"SELECT * FROM cuotas WHERE {fk}=? ORDER BY {num_col} ASC;", (prestamo_id,)).fetchall()
            last_paid = 0
            last_paid_fecha = date.fromisoformat(p["fecha_credito"])
            has_ipg = "interes_pagado" in cols
            has_abcap = "abono_capital" in cols
            has_estado = "estado" in cols

            for r in rows:
                numero = int(r[num_col])
                estado_c = (r["estado"] if has_estado else "PENDIENTE") or "PENDIENTE"
                ipg = float(r["interes_pagado"]) if has_ipg else 0.0
                abcap = float(r["abono_capital"]) if has_abcap else 0.0
                if estado_c == "PAGADO" or ipg > 0 or abcap > 0:
                    if numero > last_paid:
                        last_paid = numero
                    try:
                        last_paid_fecha = date.fromisoformat(r[fecha_col]) if r[fecha_col] else last_paid_fecha
                    except Exception:
                        pass

            conn.execute(f"DELETE FROM cuotas WHERE {fk}=? AND {num_col}>?;", (prestamo_id, last_paid))

            modalidad = data.modalidad or p["modalidad"]
            for i, c in enumerate(data.plan, start=1):
                nro = last_paid + i
                base_date = last_paid_fecha
                next_date = (
                    _calc_due_guarded(base_date, modalidad, 1)
                    if last_paid > 0
                    else _calc_due_guarded(date.fromisoformat(p["fecha_credito"]), modalidad, i)
                )
                _insert_cuota_flexible(conn, prestamo_id, nro, next_date.isoformat(), float(c.capital), float(c.interes))

            new_count = last_paid + len(data.plan)
            conn.execute(
                "UPDATE prestamos SET num_cuotas=?, modalidad=? WHERE id=?;",
                (new_count, modalidad, prestamo_id),
            )
            conn.commit()
        except sqlite3.Error as e:
            raise HTTPException(status_code=400, detail=f"Error SQL en replan: {e}")
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(status_code=400, detail=f"Error inesperado en replan: {type(e).__name__}: {e}")

        return {
            "id": prestamo_id,
            "notice": f"Se regeneraron {len(data.plan)} cuotas a partir de la cuota {last_paid + 1}.",
            "last_paid_num": last_paid,
            "num_cuotas": new_count,
            "plan_mode": "manual",
            "modalidad": modalidad,
        }

# ESTADO CANÓNICO (no modifica datos)
def _estado_prestamo_canonico(conn, prestamo_id: int) -> Dict[str, Any]:
    if not (_table_exists(conn, "prestamos") and _table_exists(conn, "cuotas")):
        raise HTTPException(status_code=500, detail="Tablas requeridas no existen")

    cols = _cols(conn, "cuotas")
    fk = _pick(["id_prestamo", "prestamo_id"], cols) or "id_prestamo"
    venc = _pick(["fecha_vencimiento", "fecha"], cols) or "fecha_vencimiento"

    abonos_existe = _table_exists(conn, "abonos_capital")
    ab_sum_expr = (
        "COALESCE((SELECT SUM(a.monto) FROM abonos_capital a WHERE a.id_prestamo=p.id), 0)"
        if abonos_existe
        else "0"
    )

    row_p = conn.execute("SELECT id, importe_credito FROM prestamos p WHERE id=?;", (prestamo_id,)).fetchone()
    if not row_p:
        raise HTTPException(status_code=404, detail="Préstamo no encontrado")
    importe_credito = float(row_p["importe_credito"] or 0)

    total = conn.execute(f"SELECT COUNT(*) AS c FROM cuotas WHERE {fk}=?;", (prestamo_id,)).fetchone()["c"]
    pagadas = conn.execute(
        f"SELECT COUNT(*) AS c FROM cuotas WHERE {fk}=? AND UPPER(estado)='PAGADO';",
        (prestamo_id,),
    ).fetchone()["c"]
    hoy = date.today().isoformat()
    vencidas_pendientes = conn.execute(
        f"SELECT COUNT(*) AS c FROM cuotas WHERE {fk}=? AND UPPER(estado)='PENDIENTE' AND date({venc}) < date(?);",
        (prestamo_id, hoy),
    ).fetchone()["c"]

    cap_row = conn.execute(
        f"SELECT (p.importe_credito - {ab_sum_expr}) AS capital_pendiente FROM prestamos p WHERE p.id=?;",
        (prestamo_id,),
    ).fetchone()
    capital_pendiente = float(cap_row["capital_pendiente"] or 0)

    vence_row = conn.execute(
        f"SELECT MAX(date({venc})) AS vence_ultima_cuota FROM cuotas WHERE {fk}=?;",
        (prestamo_id,),
    ).fetchone()
    vence_ultima_cuota = vence_row["vence_ultima_cuota"]

    if int(total or 0) == 0:
        estado = "PENDIENTE"
    elif int(pagadas or 0) == int(total or 0) and capital_pendiente <= 0:
        estado = "PAGADO"
    elif int(vencidas_pendientes or 0) > 0:
        estado = "VENCIDO"
    elif int(pagadas or 0) == int(total or 0) and capital_pendiente > 0:
        estado = "VENCIDO"
    else:
        estado = "PENDIENTE"

    return {
        "id": prestamo_id,
        "estado": estado,
        "capital_pendiente": capital_pendiente,
        "cuotas_total": int(total or 0),
        "cuotas_pagadas": int(pagadas or 0),
        "cuotas_vencidas_pendientes": int(vencidas_pendientes or 0),
        "vence_ultima_cuota": vence_ultima_cuota,
        "importe_credito": importe_credito,
        "fecha_referencia": hoy,
    }

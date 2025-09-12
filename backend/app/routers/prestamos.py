# backend/app/routers/prestamos.py
# Router de préstamos: listado, obtener, crear (auto y manual), actualizar (auto / manual),
# obtener plan completo, replan (editar solo pendientes y agregar cuotas).
# Diseñado para NO romper compatibilidad con el frontend actual.

from __future__ import annotations

from datetime import date, datetime, timedelta
from typing import List, Literal, Optional, Dict, Any

from fastapi import APIRouter, HTTPException, Query, BackgroundTasks
from pydantic import BaseModel, Field, AliasChoices, field_validator

from app.deps import get_conn

# Intentamos importar notificaciones; si no existe, continuamos sin romper.
try:
    from app.notifications import send_loan_created_email  # (prestamo_dict, cuotas_list)
except Exception:  # pragma: no cover
    def send_loan_created_email(*args, **kwargs):
        pass  # no-op si el módulo no está disponible


router = APIRouter()


# ----------------------------- Utilidades internas ----------------------------- #

def _table_exists(conn, name: str) -> bool:
    row = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?;",
        (name,)
    ).fetchone()
    return bool(row)


def _cols(conn, table: str) -> List[str]:
    return [r["name"] for r in conn.execute(f"PRAGMA table_info({table});").fetchall()]


def _pick(cands: List[str], cols: List[str]) -> Optional[str]:
    for c in cands:
        if c in cols:
            return c
    return None


def _add_months(d: date, months: int) -> date:
    from calendar import monthrange
    y = d.year + (d.month - 1 + months) // 12
    m = (d.month - 1 + months) % 12 + 1
    last = monthrange(y, m)[1]
    return date(y, m, min(d.day, last))


def _ensure_plan_columns(conn) -> None:
    # prestamos.plan_mode
    if _table_exists(conn, "prestamos"):
        cols_p = _cols(conn, "prestamos")
        if "plan_mode" not in cols_p:
            try:
                conn.execute("ALTER TABLE prestamos ADD COLUMN plan_mode TEXT DEFAULT 'auto';")
                conn.commit()
            except Exception:
                pass
    # cuotas: columnas *_plan (para rastrear plan manual)
    if _table_exists(conn, "cuotas"):
        cols_q = _cols(conn, "cuotas")
        changed = False
        for colname, coltype in [
            ("capital_plan", "REAL NOT NULL DEFAULT 0"),
            ("interes_plan", "REAL NOT NULL DEFAULT 0"),
            ("total_plan",   "REAL NOT NULL DEFAULT 0"),
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
    # Une préstamo + cliente al shape esperado por el frontend.
    out = {
        "id": p_row["id"],
        "monto": p_row["importe_credito"],
        "modalidad": p_row["modalidad"],
        "fecha_inicio": p_row["fecha_credito"],
        "num_cuotas": p_row["num_cuotas"],
        "tasa_interes": p_row["tasa_interes"],
        "estado": p_row["estado"] if "estado" in p_row.keys() else "PENDIENTE",
    }
    c = conn.execute(
        "SELECT id, codigo, nombre FROM clientes WHERE codigo = ?;",
        (p_row["cod_cli"],)
    ).fetchone()
    out["cliente"] = {
        "id": c["id"] if c else None,
        "codigo": c["codigo"] if c else p_row["cod_cli"],
        "nombre": c["nombre"] if c else "",
    }
    return out


def _calc_due(fecha_inicio: date, modalidad: str, n: int) -> date:
    if modalidad == "Mensual":
        return _add_months(fecha_inicio, n)
    return fecha_inicio + timedelta(days=15 * n)


def _capital_pendiente(conn, prestamo_id: int, monto_total: float) -> float:
    cols_q = _cols(conn, "cuotas")
    has_abcap = "abono_capital" in cols_q
    if not has_abcap:
        return round(monto_total, 2)
    fk = _pick(["id_prestamo", "prestamo_id"], cols_q) or "id_prestamo"
    row = conn.execute(
        f"SELECT COALESCE(SUM(COALESCE(abono_capital,0)),0) AS s FROM cuotas WHERE {fk}=?;",
        (prestamo_id,)
    ).fetchone()
    return round(monto_total - float(row["s"]), 2)


# ----------------------------- Modelos Pydantic ----------------------------- #

class PrestamoCreateIn(BaseModel):
    cod_cli: str = Field(min_length=1, validation_alias=AliasChoices("cod_cli", "codigo"))
    monto: float = Field(gt=0, validation_alias=AliasChoices("monto", "importe_credito"))
    modalidad: Literal["Mensual", "Quincenal"]
    fecha_inicio: date = Field(validation_alias=AliasChoices("fecha_inicio", "fecha_credito"))
    num_cuotas: int = Field(gt=0, validation_alias=AliasChoices("num_cuotas", "numero_cuotas"))
    tasa_interes: float = Field(ge=0)

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


class _CuotaPlanIn(BaseModel):
    capital: float = Field(ge=0)
    interes: float = Field(ge=0)


class PrestamoManualIn(BaseModel):
    cod_cli: str = Field(min_length=1, validation_alias=AliasChoices("cod_cli", "codigo"))
    monto: float = Field(gt=0, validation_alias=AliasChoices("monto", "importe_credito"))
    modalidad: Literal["Mensual", "Quincenal"]
    fecha_inicio: date = Field(validation_alias=AliasChoices("fecha_inicio", "fecha_credito"))
    num_cuotas: int = Field(gt=0, validation_alias=AliasChoices("num_cuotas", "numero_cuotas"))
    tasa: float = Field(ge=0)
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

    @field_validator("plan")
    @classmethod
    def _len_match(cls, v, info):
        n = info.data.get("num_cuotas")
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
        if v is None:
            return v
        if isinstance(v, str):
            s = v.strip().lower()
            if s.startswith("men"):
                return "Mensual"
            if s.startswith("quin"):
                return "Quincenal"
        return v


# -------------------------------- Endpoints --------------------------------- #

@router.get("")
def listar_prestamos(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=500),
    cod_cli: Optional[str] = Query(None)
):
    """Listado para la lista principal del frontend."""
    with get_conn() as conn:
        if not _table_exists(conn, "prestamos"):
            return {"total": 0, "items": []}

        where = []
        params: List[Any] = []
        if cod_cli:
            where.append("p.cod_cli = ?")
            params.append(cod_cli.strip())
        where_sql = f"WHERE {' AND '.join(where)}" if where else ""

        total = conn.execute(f"SELECT COUNT(*) AS c FROM prestamos p {where_sql};", params).fetchone()["c"]

        rows = conn.execute(
            f"""
            SELECT p.*
              FROM prestamos p
            {where_sql}
            ORDER BY p.id DESC
            LIMIT ? OFFSET ?;
            """,
            (*params, page_size, (page - 1) * page_size)
        ).fetchall()

        items = [_prestamo_to_front(conn, r) for r in rows]
        return {"total": total, "items": items}


@router.get("/{prestamo_id}")
def obtener_prestamo(prestamo_id: int):
    with get_conn() as conn:
        p = conn.execute("SELECT * FROM prestamos WHERE id=?", (prestamo_id,)).fetchone()
        if not p:
            raise HTTPException(status_code=404, detail="Préstamo no encontrado")
        return _prestamo_to_front(conn, p)


@router.post("")
def crear_prestamo_auto(data: PrestamoCreateIn, bg: BackgroundTasks):
    """Crea préstamo AUTOMÁTICO (interés fijo por período; capital flexible)."""
    with get_conn() as conn:
        _ensure_plan_columns(conn)

        # Insert cabecera
        cur = conn.execute(
            "INSERT INTO prestamos (cod_cli, importe_credito, modalidad, fecha_credito, num_cuotas, tasa_interes, plan_mode, estado) "
            "VALUES (?, ?, ?, ?, ?, ?, 'auto', 'PENDIENTE');",
            (data.cod_cli.strip(), float(data.monto), data.modalidad, data.fecha_inicio.isoformat(),
             int(data.num_cuotas), float(data.tasa_interes))
        )
        prestamo_id = cur.lastrowid

        # Insert cuotas
        cols_q = _cols(conn, "cuotas") if _table_exists(conn, "cuotas") else []
        if cols_q:
            fk = _pick(["id_prestamo", "prestamo_id"], cols_q) or "id_prestamo"
            num = "cuota_numero" if "cuota_numero" in cols_q else ("numero" if "numero" in cols_q else "cuota_numero")
            fecha_col = "fecha_vencimiento" if "fecha_vencimiento" in cols_q else ("fecha" if "fecha" in cols_q else "fecha_vencimiento")
            iap_col = _pick(["interes_a_pagar", "interes"], cols_q) or "interes_a_pagar"
            has_ipg = "interes_pagado" in cols_q
            has_capital = "capital" in cols_q
            has_total = "total" in cols_q

            i_per = round(float(data.monto) * (float(data.tasa_interes) / 100.0), 2)
            for i in range(1, int(data.num_cuotas) + 1):
                fields = [fk, num, fecha_col, iap_col, "estado"]
                values = [prestamo_id, i, _calc_due(data.fecha_inicio, data.modalidad, i).isoformat(), i_per, "PENDIENTE"]
                if has_ipg:
                    fields += ["interes_pagado"]; values += [0.0]
                if has_capital:
                    fields += ["capital"]; values += [0.0]
                if has_total:
                    fields += ["total"]; values += [i_per]
                sql = f"INSERT INTO cuotas ({', '.join(fields)}) VALUES ({', '.join(['?'] * len(values))});"
                conn.execute(sql, values)

        conn.commit()

        # Respuesta + email en background
        res = _prestamo_to_front(conn, conn.execute("SELECT * FROM prestamos WHERE id=?", (prestamo_id,)).fetchone())
        # Construimos un resumen de cuotas para el correo
        cuotas = []
        if _table_exists(conn, "cuotas"):
            cols_q = _cols(conn, "cuotas")
            fk = _pick(["id_prestamo", "prestamo_id"], cols_q) or "id_prestamo"
            num = "cuota_numero" if "cuota_numero" in cols_q else ("numero" if "numero" in cols_q else "cuota_numero")
            fecha_col = "fecha_vencimiento" if "fecha_vencimiento" in cols_q else ("fecha" if "fecha" in cols_q else "fecha_vencimiento")
            iap_col = _pick(["interes_a_pagar", "interes"], cols_q) or "interes_a_pagar"
            rows = conn.execute(
                f"SELECT {num} AS numero, {fecha_col} AS fecha, {iap_col} AS interes FROM cuotas WHERE {fk}=? ORDER BY {num};",
                (prestamo_id,)
            ).fetchall()
            cuotas = [{"numero": r["numero"], "fecha": r["fecha"], "interes": float(r["interes"])} for r in rows]

        try:
            bg.add_task(send_loan_created_email, res, cuotas)
        except Exception:
            pass

        # El frontend de "new_loan_page" espera también las cuotas de respuesta
        res["cuotas"] = [
            {"id": None, "numero": c["numero"], "fecha_vencimiento": c["fecha"], "interes_a_pagar": c["interes"],
             "interes_pagado": 0.0, "estado": "PENDIENTE"}
            for c in cuotas
        ]
        return res


@router.post("/manual")
def crear_prestamo_manual(data: PrestamoManualIn, bg: BackgroundTasks):
    """Crea préstamo MANUAL con plan completo (capital+interés por cuota)."""
    tol = 0.01
    plan_capital = round(sum(float(x.capital) for x in data.plan), 2)
    monto = round(float(data.monto), 2)
    if abs(monto - plan_capital) > tol:
        diff = round(monto - plan_capital, 2)
        raise HTTPException(status_code=400, detail=f"La suma de capital del plan debe ser {monto:.2f}. Actual: {plan_capital:.2f} (diff {diff:+.2f})")

    with get_conn() as conn:
        _ensure_plan_columns(conn)
        # Inserta cabecera
        cur = conn.execute(
            "INSERT INTO prestamos (cod_cli, importe_credito, modalidad, fecha_credito, num_cuotas, tasa_interes, plan_mode, estado) "
            "VALUES (?, ?, ?, ?, ?, ?, 'manual', 'PENDIENTE');",
            (data.cod_cli.strip(), float(data.monto), data.modalidad, data.fecha_inicio.isoformat(),
             int(data.num_cuotas), float(data.tasa))
        )
        prestamo_id = cur.lastrowid

        # Inserta cuotas manuales
        cols_q = _cols(conn, "cuotas") if _table_exists(conn, "cuotas") else []
        if cols_q:
            fk = _pick(["id_prestamo", "prestamo_id"], cols_q) or "id_prestamo"
            num = "cuota_numero" if "cuota_numero" in cols_q else ("numero" if "numero" in cols_q else "cuota_numero")
            fecha_col = "fecha_vencimiento" if "fecha_vencimiento" in cols_q else ("fecha" if "fecha" in cols_q else "fecha_vencimiento")
            iap_col = _pick(["interes_a_pagar", "interes"], cols_q) or "interes_a_pagar"
            has_ipg = "interes_pagado" in cols_q
            has_capital = "capital" in cols_q
            has_total = "total" in cols_q

            for i, c in enumerate(data.plan, start=1):
                fv = _calc_due(data.fecha_inicio, data.modalidad, i).isoformat()
                fields = [fk, num, fecha_col, iap_col, "estado"]
                values = [prestamo_id, i, fv, float(c.interes), "PENDIENTE"]
                if has_ipg:
                    fields += ["interes_pagado"]; values += [0.0]
                # Guardamos el plan manual
                cols_q2 = _cols(conn, "cuotas")
                if "capital_plan" in cols_q2:
                    fields += ["capital_plan"]; values += [float(c.capital)]
                if "interes_plan" in cols_q2:
                    fields += ["interes_plan"]; values += [float(c.interes)]
                if "total_plan" in cols_q2:
                    fields += ["total_plan"]; values += [round(float(c.capital) + float(c.interes), 2)]
                # Compatibilidad UI
                if has_capital:
                    fields += ["capital"]; values += [float(c.capital)]
                if has_total:
                    fields += ["total"]; values += [round(float(c.capital) + float(c.interes), 2)]

                sql = f"INSERT INTO cuotas ({', '.join(fields)}) VALUES ({', '.join(['?'] * len(values))});"
                conn.execute(sql, values)

        conn.commit()

        res = _prestamo_to_front(conn, conn.execute("SELECT * FROM prestamos WHERE id=?", (prestamo_id,)).fetchone())
        cuotas = []
        if _table_exists(conn, "cuotas"):
            cols_q = _cols(conn, "cuotas")
            fk = _pick(["id_prestamo", "prestamo_id"], cols_q) or "id_prestamo"
            num = "cuota_numero" if "cuota_numero" in cols_q else ("numero" if "numero" in cols_q else "cuota_numero")
            fecha_col = "fecha_vencimiento" if "fecha_vencimiento" in cols_q else ("fecha" if "fecha" in cols_q else "fecha_vencimiento")
            iap_col = _pick(["interes_a_pagar", "interes"], cols_q) or "interes_a_pagar"
            rows = conn.execute(
                f"SELECT {num} AS numero, {fecha_col} AS fecha, {iap_col} AS interes FROM cuotas WHERE {fk}=? ORDER BY {num};",
                (prestamo_id,)
            ).fetchall()
            cuotas = [{"numero": r["numero"], "fecha": r["fecha"], "interes": float(r["interes"])} for r in rows]

        try:
            bg.add_task(send_loan_created_email, res, cuotas)
        except Exception:
            pass

        res["cuotas"] = [
            {"id": None, "numero": c["numero"], "fecha_vencimiento": c["fecha"], "interes_a_pagar": c["interes"],
             "interes_pagado": 0.0, "estado": "PENDIENTE"}
            for c in cuotas
        ]
        return res


@router.put("/{prestamo_id}")
def actualizar_prestamo_automatico(prestamo_id: int, data: PrestamoAutoUpdateIn):
    """
    Actualiza cabecera de un préstamo AUTOMÁTICO y regenera cuotas.
    Prohibido si plan_mode == 'manual', si hay pagos o si está PAGADO.
    """
    with get_conn() as conn:
        if not _table_exists(conn, "prestamos"):
            raise HTTPException(status_code=500, detail="No existe tabla 'prestamos'")
        p = conn.execute("SELECT * FROM prestamos WHERE id=?", (prestamo_id,)).fetchone()
        if not p:
            raise HTTPException(status_code=404, detail="Préstamo no encontrado")

        plan_mode = p["plan_mode"] if "plan_mode" in p.keys() else "auto"
        estado = p["estado"] if "estado" in p.keys() else "PENDIENTE"
        if plan_mode == "manual":
            raise HTTPException(status_code=400, detail="Este préstamo es manual; usa PUT /prestamos/{id}/manual")
        if estado == "PAGADO":
            raise HTTPException(status_code=400, detail="No se puede editar un préstamo ya pagado")

        # Bloquear si hay pagos
        if _table_exists(conn, "cuotas"):
            cols_q = _cols(conn, "cuotas")
            fk = _pick(["id_prestamo", "prestamo_id"], cols_q) or "id_prestamo"
            q = conn.execute(
                f"SELECT COUNT(*) AS c FROM cuotas WHERE {fk}=? AND (estado='PAGADO' OR COALESCE(interes_pagado,0)>0 OR COALESCE(abono_capital,0)>0);",
                (prestamo_id,)
            ).fetchone()
            if int(q["c"] or 0) > 0:
                raise HTTPException(status_code=400, detail="No se puede editar: hay cuotas con pagos registrados")

        # Actualizar cabecera
        conn.execute(
            "UPDATE prestamos SET cod_cli=?, importe_credito=?, modalidad=?, fecha_credito=?, num_cuotas=?, tasa_interes=? WHERE id=?;",
            (data.cod_cli.strip(), float(data.monto), data.modalidad, data.fecha_inicio.isoformat(),
             int(data.num_cuotas), float(data.tasa_interes), prestamo_id)
        )

        # Regenerar cuotas
        if _table_exists(conn, "cuotas"):
            cols_q = _cols(conn, "cuotas")
            fk = _pick(["id_prestamo", "prestamo_id"], cols_q) or "id_prestamo"
            num = "cuota_numero" if "cuota_numero" in cols_q else ("numero" if "numero" in cols_q else "cuota_numero")
            fecha_col = "fecha_vencimiento" if "fecha_vencimiento" in cols_q else ("fecha" if "fecha" in cols_q else "fecha_vencimiento")
            iap_col = _pick(["interes_a_pagar", "interes"], cols_q) or "interes_a_pagar"
            has_ipg = "interes_pagado" in cols_q
            has_capital = "capital" in cols_q
            has_total = "total" in cols_q

            conn.execute(f"DELETE FROM cuotas WHERE {fk}=?;", (prestamo_id,))

            i_per = round(float(data.monto) * (float(data.tasa_interes) / 100.0), 2)
            for i in range(1, int(data.num_cuotas) + 1):
                fv = _calc_due(data.fecha_inicio, data.modalidad, i).isoformat()
                fields = [fk, num, fecha_col, iap_col, "estado"]
                values = [prestamo_id, i, fv, i_per, "PENDIENTE"]
                if has_ipg:
                    fields += ["interes_pagado"]; values += [0.0]
                if has_capital:
                    fields += ["capital"]; values += [0.0]
                if has_total:
                    fields += ["total"]; values += [i_per]
                sql = f"INSERT INTO cuotas ({', '.join(fields)}) VALUES ({', '.join(['?'] * len(values))});"
                conn.execute(sql, values)

        conn.commit()

        row = conn.execute("SELECT * FROM prestamos WHERE id=?", (prestamo_id,)).fetchone()
        return _prestamo_to_front(conn, row)



@router.put("/{prestamo_id}/manual")
def actualizar_prestamo_manual(prestamo_id: int, data: PrestamoManualIn):
    """Actualiza cabecera + plan de un préstamo MANUAL, solo si no hay pagos."""
    tol = 0.01
    plan_capital = round(sum(float(x.capital) for x in data.plan), 2)
    monto = round(float(data.monto), 2)
    if abs(monto - plan_capital) > tol:
        diff = round(monto - plan_capital, 2)
        raise HTTPException(status_code=400, detail=f"La suma de capital del plan debe ser {monto:.2f}. Actual: {plan_capital:.2f} (diff {diff:+.2f})")

    with get_conn() as conn:
        p = conn.execute("SELECT * FROM prestamos WHERE id=?", (prestamo_id,)).fetchone()
        if not p:
            raise HTTPException(status_code=404, detail="Préstamo no encontrado")

        plan_mode = p["plan_mode"] if "plan_mode" in p.keys() else "auto"
        estado = p["estado"] if "estado" in p.keys() else "PENDIENTE"
        if plan_mode != "manual":
            raise HTTPException(status_code=400, detail="Este préstamo no es de modo manual")
        if estado == "PAGADO":
            raise HTTPException(status_code=400, detail="No se puede editar un préstamo ya pagado")

        # Bloquear si hay pagos
        if _table_exists(conn, "cuotas"):
            cols_q = _cols(conn, "cuotas")
            fk = _pick(["id_prestamo", "prestamo_id"], cols_q) or "id_prestamo"
            q = conn.execute(
                f"SELECT COUNT(*) AS c FROM cuotas WHERE {fk}=? AND (estado='PAGADO' OR COALESCE(interes_pagado,0)>0 OR COALESCE(abono_capital,0)>0);",
                (prestamo_id,)
            ).fetchone()
            if int(q["c"] or 0) > 0:
                raise HTTPException(status_code=400, detail="No se puede editar: hay cuotas con pagos registrados")

        _ensure_plan_columns(conn)

        # Actualizar cabecera
        conn.execute(
            "UPDATE prestamos SET cod_cli=?, importe_credito=?, modalidad=?, fecha_credito=?, num_cuotas=?, tasa_interes=? WHERE id=?;",
            (data.cod_cli.strip(), float(data.monto), data.modalidad, data.fecha_inicio.isoformat(), int(data.num_cuotas), float(data.tasa), prestamo_id)
        )

        # Regenerar cuotas manuales
        if _table_exists(conn, "cuotas"):
            cols_q = _cols(conn, "cuotas")
            fk = _pick(["id_prestamo", "prestamo_id"], cols_q) or "id_prestamo"
            num = "cuota_numero" if "cuota_numero" in cols_q else ("numero" if "numero" in cols_q else "cuota_numero")
            fecha_col = "fecha_vencimiento" if "fecha_vencimiento" in cols_q else ("fecha" if "fecha" in cols_q else "fecha_vencimiento")
            iap_col = _pick(["interes_a_pagar", "interes"], cols_q) or "interes_a_pagar"
            has_ipg = "interes_pagado" in cols_q
            has_capital = "capital" in cols_q
            has_total = "total" in cols_q

            conn.execute(f"DELETE FROM cuotas WHERE {fk}=?;", (prestamo_id,))

            for i, c in enumerate(data.plan, start=1):
                fv = _calc_due(data.fecha_inicio, data.modalidad, i).isoformat()
                fields = [fk, num, fecha_col, iap_col, "estado"]
                values = [prestamo_id, i, fv, float(c.interes), "PENDIENTE"]
                if has_ipg:
                    fields += ["interes_pagado"]; values += [0.0]
                cols_q2 = _cols(conn, "cuotas")
                if "capital_plan" in cols_q2:
                    fields += ["capital_plan"]; values += [float(c.capital)]
                if "interes_plan" in cols_q2:
                    fields += ["interes_plan"]; values += [float(c.interes)]
                if "total_plan" in cols_q2:
                    fields += ["total_plan"]; values += [round(float(c.capital) + float(c.interes), 2)]
                if has_capital:
                    fields += ["capital"]; values += [float(c.capital)]
                if has_total:
                    fields += ["total"]; values += [round(float(c.capital) + float(c.interes), 2)]
                sql = f"INSERT INTO cuotas ({', '.join(fields)}) VALUES ({', '.join(['?'] * len(values))});"
                conn.execute(sql, values)

        conn.commit()
        row = conn.execute("SELECT * FROM prestamos WHERE id=?", (prestamo_id,)).fetchone()
        return _prestamo_to_front(conn, row)


@router.get("/{prestamo_id}/plan")
def obtener_plan_prestamo(prestamo_id: int):
    """
    Devuelve cabecera y plan completo, marcando cuotas editables vs pagadas
    y el índice de la última cuota con pagos (last_paid_num).
    """
    with get_conn() as conn:
        if not _table_exists(conn, "prestamos"):
            raise HTTPException(status_code=500, detail="No existe tabla 'prestamos'")
        p = conn.execute("SELECT * FROM prestamos WHERE id=?", (prestamo_id,)).fetchone()
        if not p:
            raise HTTPException(status_code=404, detail="Préstamo no encontrado")

        plan_mode = p["plan_mode"] if "plan_mode" in p.keys() else "auto"
        out = {
            "id": p["id"],
            "cod_cli": p["cod_cli"],
            "monto": p["importe_credito"],
            "modalidad": p["modalidad"],
            "fecha_inicio": p["fecha_credito"],
            "num_cuotas": p["num_cuotas"],
            "tasa": p["tasa_interes"],
            "plan_mode": plan_mode,
            "estado": p["estado"] if "estado" in p.keys() else "PENDIENTE",
            "plan": [],
            "last_paid_num": 0,
        }

        if not _table_exists(conn, "cuotas"):
            return out

        cols_q = _cols(conn, "cuotas")
        fk = _pick(["id_prestamo", "prestamo_id"], cols_q) or "id_prestamo"
        num = "cuota_numero" if "cuota_numero" in cols_q else ("numero" if "numero" in cols_q else "cuota_numero")
        fecha_col = "fecha_vencimiento" if "fecha_vencimiento" in cols_q else ("fecha" if "fecha" in cols_q else "fecha_vencimiento")
        cap_src = "capital_plan" if "capital_plan" in cols_q else ("capital" if "capital" in cols_q else None)
        int_src = "interes_plan" if "interes_plan" in cols_q else ("interes_a_pagar" if "interes_a_pagar" in cols_q else ("interes" if "interes" in cols_q else None))
        has_ipg = "interes_pagado" in cols_q
        has_abcap = "abono_capital" in cols_q
        has_estado = "estado" in cols_q

        rows = conn.execute(
            f"SELECT * FROM cuotas WHERE {fk}=? ORDER BY {num} ASC;",
            (prestamo_id,)
        ).fetchall()

        last_paid = 0
        for r in rows:
            numero = int(r[num])
            estado = (r["estado"] if has_estado else "PENDIENTE") or "PENDIENTE"
            ipg = float(r["interes_pagado"]) if has_ipg else 0.0
            abcap = float(r["abono_capital"]) if has_abcap else 0.0
            if estado == "PAGADO" or ipg > 0 or abcap > 0:
                last_paid = max(last_paid, numero)
            c = float(r[cap_src]) if cap_src else 0.0
            i = float(r[int_src]) if int_src else 0.0
            out["plan"].append({
                "numero": numero,
                "fecha": r[fecha_col],
                "capital": c,
                "interes": i,
                "estado": estado,
                "interes_pagado": ipg,
                "abono_capital": abcap,
                "editable": numero > last_paid
            })

        out["last_paid_num"] = last_paid
        return out


@router.put("/{prestamo_id}/replan")
def replan_prestamo(prestamo_id: int, data: PrestamoReplanIn):
    """
    Reprograma las CUOTAS PENDIENTES a partir de la última cuota con pagos.
    - Respeta cuotas ya pagadas (o con pagos).
    - Reemplaza TODAS las pendientes por el plan dado y permite AGREGAR más.
    - Valida que Σ(capital nuevo) == capital pendiente real (monto - Σ abonos ya registrados).
    - Ajusta fechas continuando la periodicidad desde la última fecha base.
    """
    tol = 0.01
    with get_conn() as conn:
        if not _table_exists(conn, "prestamos"):
            raise HTTPException(status_code=500, detail="No existe tabla 'prestamos'")
        p = conn.execute("SELECT * FROM prestamos WHERE id=?", (prestamo_id,)).fetchone()
        if not p:
            raise HTTPException(status_code=404, detail="Préstamo no encontrado")

        _ensure_plan_columns(conn)

        modalidad = data.modalidad or p["modalidad"]
        monto_total = float(p["importe_credito"])
        fecha_inicio = date.fromisoformat(p["fecha_credito"])
        plan_mode = p["plan_mode"] if "plan_mode" in p.keys() else "auto"

        if not _table_exists(conn, "cuotas"):
            raise HTTPException(status_code=500, detail="No existe tabla 'cuotas'")

        cols_q = _cols(conn, "cuotas")
        fk = _pick(["id_prestamo", "prestamo_id"], cols_q) or "id_prestamo"
        num = "cuota_numero" if "cuota_numero" in cols_q else ("numero" if "numero" in cols_q else "cuota_numero")
        fecha_col = "fecha_vencimiento" if "fecha_vencimiento" in cols_q else ("fecha" if "fecha" in cols_q else "fecha_vencimiento")
        has_capital = "capital" in cols_q
        has_total = "total" in cols_q
        has_ipg = "interes_pagado" in cols_q
        has_abcap = "abono_capital" in cols_q

        # Detectar última cuota con pagos
        rows = conn.execute(
            f"SELECT * FROM cuotas WHERE {fk}=? ORDER BY {num} ASC;",
            (prestamo_id,)
        ).fetchall()
        last_paid = 0
        last_paid_fecha = fecha_inicio
        for r in rows:
            numero = int(r[num])
            estado = (r["estado"] if "estado" in r.keys() else "PENDIENTE") or "PENDIENTE"
            ipg = float(r["interes_pagado"]) if has_ipg else 0.0
            abcap = float(r["abono_capital"]) if has_abcap else 0.0
            if estado == "PAGADO" or ipg > 0 or abcap > 0:
                last_paid = max(last_paid, numero)
                try:
                    last_paid_fecha = date.fromisoformat(r[fecha_col])
                except Exception:
                    pass

        # Validar capital pendiente
        capital_pendiente = _capital_pendiente(conn, prestamo_id, monto_total)
        plan_capital = round(sum(float(x.capital) for x in data.plan), 2)
        if abs(plan_capital - capital_pendiente) > tol:
            diff = round(capital_pendiente - plan_capital, 2)
            raise HTTPException(
                status_code=400,
                detail=f"El capital del nuevo plan debe ser {capital_pendiente:.2f}. Actual: {plan_capital:.2f} (diff {diff:+.2f})"
            )

        # Borrar cuotas pendientes y reinsertar según nuevo plan
        conn.execute(f"DELETE FROM cuotas WHERE {fk}=? AND {num}>?;", (prestamo_id, last_paid))

        def _next_fecha(base: date, k: int) -> date:
            return _add_months(base, k) if modalidad == "Mensual" else base + timedelta(days=15 * k)

        for i, c in enumerate(data.plan, start=1):
            numero = last_paid + i
            fv = _next_fecha(last_paid_fecha, i).isoformat()
            fields = [fk, num, fecha_col, "estado", "interes_a_pagar"]
            values = [prestamo_id, numero, fv, "PENDIENTE", float(c.interes)]
            if has_ipg:
                fields += ["interes_pagado"]; values += [0.0]
            cols_q2 = _cols(conn, "cuotas")
            if "capital_plan" in cols_q2:
                fields += ["capital_plan"]; values += [float(c.capital)]
            if "interes_plan" in cols_q2:
                fields += ["interes_plan"]; values += [float(c.interes)]
            if "total_plan" in cols_q2:
                fields += ["total_plan"]; values += [round(float(c.capital) + float(c.interes), 2)]
            if has_capital:
                fields += ["capital"]; values += [float(c.capital)]
            if has_total:
                fields += ["total"]; values += [round(float(c.capital) + float(c.interes), 2)]
            sql = f"INSERT INTO cuotas ({', '.join(fields)}) VALUES ({', '.join(['?'] * len(values))});"
            conn.execute(sql, values)

        # Actualizar num_cuotas total y modalidad (si cambió)
        new_count = last_paid + len(data.plan)
        conn.execute("UPDATE prestamos SET num_cuotas=?, modalidad=? WHERE id=?;", (new_count, modalidad, prestamo_id))

        conn.commit()

        return {
            "id": prestamo_id,
            "notice": f"Se regeneraron {len(data.plan)} cuotas a partir de la cuota {last_paid + 1}.",
            "last_paid_num": last_paid,
            "num_cuotas": new_count,
            "plan_mode": plan_mode,
            "modalidad": modalidad,
        }

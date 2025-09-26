import re, textwrap, pathlib

path = pathlib.Path("backend/app/routers/cuotas.py")
s = path.read_text(encoding="utf-8", errors="ignore")

# Normaliza tabs a 4 espacios (evita errores de indentación)
s = s.replace("\t", "    ")

def patch_function(body: str, guard_block: str) -> str:
    # Quita "estado='PAGADO'" dentro del UPDATE (si estuviera)
    body = re.sub(r"(\bUPDATE\s+cuotas\s+SET\b[^;]*?)\bestado\s*=\s*'PAGADO'\s*,\s*", r"\1",
                  body, flags=re.IGNORECASE|re.DOTALL)
    body = re.sub(r"\b,\s*estado\s*=\s*'PAGADO'\s*(,|\s)*", r"\1", body, flags=re.IGNORECASE)
    body = re.sub(r"\bSET\s+estado\s*=\s*'PAGADO'\s*(,|\s)*", r"SET ", body, flags=re.IGNORECASE)

    # Inserta la guardia antes del primer conn.commit() (o al final si no hay)
    m = re.search(r"conn\.commit\(\)", body)
    insert_at = m.start() if m else len(body)
    return body[:insert_at] + guard_block + body[insert_at:]

def patch_endpoint(source: str, route_regex: str, guard_block: str) -> str:
    m = re.search(route_regex, source, flags=re.DOTALL)
    if not m:
        return source  # no se encontró el endpoint; no tocar
    head_end = m.end()
    tail = source[head_end:]
    m2 = re.search(r"\n@router\.(post|get|put|delete)\(|\ndef\s+\w+\(", tail)
    body_end = head_end + (m2.start() if m2 else len(tail))
    header = source[:head_end]
    body = source[head_end:body_end]
    footer = source[body_end:]
    new_body = patch_function(body, guard_block)
    return header + new_body + footer

guard_pago = textwrap.indent("""
# --- Guardia de estado: marcar PAGADO solo si interés y capital de la CUOTA están cubiertos ---
try:
    cols = _cols(conn, "cuotas")
    m = _cuota_mapping(conn)
    cap_plan_col = "capital_plan" if "capital_plan" in cols else ("capital" if "capital" in cols else None)
    interes_plan_col = "interes_a_pagar" if "interes_a_pagar" in cols else ("interes" if "interes" in cols else None)

    cur = conn.execute("SELECT * FROM cuotas WHERE id=?;", (cuota_id,)).fetchone()
    _ip_col = m.get("interes_pagado", "interes_pagado")
    _ab_col = m.get("abono_capital", "abono_capital")

    interes_pagado = float(cur[_ip_col] or 0) if _ip_col in cur.keys() else 0.0
    interes_plan = float(cur[interes_plan_col] or 0) if (interes_plan_col and interes_plan_col in cur.keys()) else 0.0
    cap_plan = float(cur[cap_plan_col] or 0) if (cap_plan_col and cap_plan_col in cur.keys()) else 0.0
    abono_cuota = float(cur[_ab_col] or 0) if _ab_col in cur.keys() else 0.0

    interes_cubierto = interes_pagado >= max(interes_plan, 0.0) - 1e-6
    capital_cubierto = cap_plan <= 1e-6 or abono_cuota >= cap_plan - 1e-6
    nuevo_estado = "PAGADO" if (interes_cubierto y capital_cubierto) else "PENDIENTE"
    conn.execute(f"UPDATE cuotas SET {m['estado']}=? WHERE id=?;", (nuevo_estado, cuota_id))
except Exception:
    pass

""", "        ")

guard_abono = textwrap.indent("""
# --- Verificación de cierre de cuota: si interés y capital cubiertos, marcar PAGADO ---
try:
    cols = _cols(conn, "cuotas")
    m = _cuota_mapping(conn)
    cap_plan_col = "capital_plan" if "capital_plan" in cols else ("capital" if "capital" in cols else None)
    interes_plan_col = "interes_a_pagar" if "interes_a_pagar" in cols else ("interes" if "interes" in cols else None)

    cur = conn.execute("SELECT * FROM cuotas WHERE id=?;", (cuota_id,)).fetchone()
    _ip_col = m.get("interes_pagado", "interes_pagado")
    _ab_col = m.get("abono_capital", "abono_capital")

    interes_pagado = float(cur[_ip_col] or 0) si _ip_col in cur.keys() else 0.0
    interes_plan = float(cur[interes_plan_col] or 0) si (interes_plan_col and interes_plan_col in cur.keys()) else 0.0
    cap_plan = float(cur[cap_plan_col] or 0) si (cap_plan_col and cap_plan_col in cur.keys()) else 0.0
    abono_cuota = float(cur[_ab_col] or 0) si _ab_col in cur.keys() else 0.0

    interes_cubierto = interes_pagado >= max(interes_plan, 0.0) - 1e-6
    capital_cubierto = cap_plan <= 1e-6 or abono_cuota >= cap_plan - 1e-6
    if interes_cubierto and capital_cubierto:
        conn.execute(f"UPDATE cuotas SET {m['estado']}='PAGADO' WHERE id=?;", (cuota_id,))
except Exception:
    pass

""", "        ")

route_pago = r"@router\.post\(\"/\{cuota_id:int\}/pago\"[^\)]*\)\s*def\s+registrar_pago\s*\([^\)]*\):"
route_abono = r"@router\.post\(\"/\{cuota_id:int\}/abono-capital\"[^\)]*\)\s*def\s+registrar_abono_capital\s*\([^\)]*\):"

s = patch_endpoint(s, route_pago, guard_pago)
s = patch_endpoint(s, route_abono, guard_abono)

path.write_text(s, encoding="utf-8")
print("OK: patched", path)

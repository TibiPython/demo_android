# backend/app/notifications.py
from __future__ import annotations

import logging
import os
import smtplib
import time
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.utils import formataddr
from typing import Any, Dict, List, Tuple

from app.deps import get_conn  # misma conexión/ruta que usa el backend

log = logging.getLogger("notifications")
if not log.handlers:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")


# ------------------ helpers ------------------

def _fmt_money(n: float | int | None) -> str:
    if n is None:
        return "-"
    s = f"{float(n):,.2f}".replace(",", "X").replace(".", ",").replace("X", ".")
    return f"$ {s}"


def _smtp_client() -> smtplib.SMTP:
    import ssl

    host = os.getenv("SMTP_HOST", "localhost")
    port = int(os.getenv("SMTP_PORT", "25"))
    user = os.getenv("SMTP_USER")
    pwd = os.getenv("SMTP_PASS")
    tls = os.getenv("SMTP_TLS", "true").lower()

    if tls in ("ssl", "465"):
        cli = smtplib.SMTP_SSL(host, port, context=ssl.create_default_context(), timeout=20)
    else:
        cli = smtplib.SMTP(host, port, timeout=20)
        if tls in ("1", "true", "yes", "on"):
            cli.starttls(context=ssl.create_default_context())
    if user and pwd:
        cli.login(user, pwd)
    return cli


def _send_email(to: List[str], subject: str, html: str, text: str | None = None, retries: int = 2) -> None:
    sender_name = os.getenv("FROM_NAME", "Soporte")
    sender_email = os.getenv("FROM_EMAIL", "no-reply@example.local")
    cc = [x.strip() for x in os.getenv("CC_EMAIL", "").split(",") if x.strip()]
    bcc = [x.strip() for x in os.getenv("BCC_EMAIL", "").split(",") if x.strip()]
    recipients = list(dict.fromkeys(to + cc + bcc))  # deduplicado preservando orden

    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = formataddr((sender_name, sender_email))
    msg["To"] = ", ".join(to)
    if cc:
        msg["Cc"] = ", ".join(cc)
    if text:
        msg.attach(MIMEText(text, "plain", "utf-8"))
    msg.attach(MIMEText(html, "html", "utf-8"))

    attempt = 0
    while True:
        try:
            cli = _smtp_client()
            cli.sendmail(sender_email, recipients, msg.as_string())
            try:
                cli.quit()
            except Exception:
                pass
            log.info("Email enviado a %s (asunto: %s)", recipients, subject)
            return
        except Exception as e:
            attempt += 1
            log.warning("Fallo enviando email (intento %s/%s): %s", attempt, retries + 1, e)
            if attempt > retries:
                log.exception("No se pudo enviar el email tras reintentos.")
                return
            time.sleep(1.5 * attempt)


# ------------------ fetch & render ------------------

def _fetch_loan_bundle(prestamo_id: int) -> Tuple[Dict[str, Any] | None, Dict[str, Any] | None, List[Dict[str, Any]]]:
    """
    Obtiene datos del préstamo, cliente y cuotas con tolerancia a diferencias de esquema.
    """
    with get_conn() as conn:
        # Cabecera préstamo/cliente
        row = conn.execute(
            """
            SELECT p.id,
                   p.importe_credito  AS monto,
                   p.modalidad,
                   p.fecha_credito    AS fecha_inicio,
                   p.num_cuotas,
                   p.tasa_interes,
                   c.id               AS cliente_id,
                   c.codigo           AS cliente_codigo,
                   c.nombre           AS cliente_nombre,
                   c.email            AS cliente_email
            FROM prestamos p
            JOIN clientes  c ON p.cod_cli = c.codigo
            WHERE p.id = ?;
            """,
            (prestamo_id,),
        ).fetchone()
        if not row:
            log.warning("Prestamo %s no encontrado", prestamo_id)
            return None, None, []

        prestamo = {
            "id": row["id"],
            "monto": row["monto"],
            "modalidad": row["modalidad"],
            "fecha_inicio": row["fecha_inicio"],
            "num_cuotas": row["num_cuotas"],
            "tasa_interes": row["tasa_interes"],
        }
        cliente = {
            "id": row["cliente_id"],
            "codigo": row["cliente_codigo"],   # NO lo mostraremos en el mail
            "nombre": row["cliente_nombre"],
            "email": row["cliente_email"],
        }

        # Descubrir columnas reales de cuotas
        cols = [r["name"] for r in conn.execute("PRAGMA table_info(cuotas);").fetchall()]

        fk_q = "id_prestamo" if "id_prestamo" in cols else ("prestamo_id" if "prestamo_id" in cols else "id_prestamo")
        num_col = "cuota_numero" if "cuota_numero" in cols else ("numero" if "numero" in cols else "cuota_numero")
        fecha_col = "fecha_vencimiento" if "fecha_vencimiento" in cols else ("fecha" if "fecha" in cols else "fecha_vencimiento")

        # Capital por cuota: capital_plan > capital > 0
        if "capital_plan" in cols:
            cap_expr = "capital_plan AS capital"
        elif "capital" in cols:
            cap_expr = "capital AS capital"
        else:
            cap_expr = "0 AS capital"

        # Interés por cuota: interes_plan > interes_a_pagar > interes > 0
        if "interes_plan" in cols:
            int_expr = "interes_plan AS interes"
        elif "interes_a_pagar" in cols:
            int_expr = "interes_a_pagar AS interes"
        elif "interes" in cols:
            int_expr = "interes AS interes"
        else:
            int_expr = "0 AS interes"

        # Total por cuota: si existe 'total', úsalo; si no, lo calcularemos en Python (capital+interes).
        total_exists = "total" in cols  # en tus dumps suele estar 'total_plan', así que calcularemos a mano
        total_select = "total" if total_exists else "NULL AS total"

        sql = (
            f"SELECT {num_col} AS numero, {fecha_col} AS fecha_venc, "
            f"{cap_expr}, {int_expr}, {total_select} "
            f"FROM cuotas WHERE {fk_q}=? ORDER BY {num_col} ASC;"
        )
        rows_q = conn.execute(sql, (prestamo_id,)).fetchall()

        cuotas: List[Dict[str, Any]] = []
        for r in rows_q:
            c = dict(r)
            # Asegurar tipos numéricos float
            def _f(v):
                try: return float(v)
                except Exception: return 0.0
            c["capital"] = _f(c.get("capital"))
            c["interes"] = _f(c.get("interes"))
            # Si no hay 'total', se calculará luego (capital + interes)
            cuotas.append(c)

        return cliente, prestamo, cuotas


def _render_loan_created(cliente: Dict[str, Any], prestamo: Dict[str, Any], cuotas: List[Dict[str, Any]]) -> Tuple[str, str, str]:
    """
    Genera el correo de préstamo creado en texto plano, sin tabla,
    siguiendo la nueva especificación: 5 puntos de información.
    """
    folio = f"P-{prestamo['id']:04d}"
    subject = f"Nuevo préstamo {folio} — {cliente.get('nombre','')}"

    # 1. Mensaje fijo
    lineas = ["El interés de cada cuota se calcula en base al abono mensual a capital.", ""]

    # 2. Nombre del cliente
    lineas.append(f"Nombre: {cliente.get('nombre','')}")

    # 3. Monto y Tasa %
    monto = float(prestamo.get("monto") or 0)
    tasa = prestamo.get("tasa_interes")
    lineas.append(f"Monto: {monto:,.2f}  |  Tasa: {tasa}%")

    # 4. Plazo y Modalidad
    lineas.append(
        f"Plazo: {prestamo.get('num_cuotas')} cuota(s)  |  Modalidad: {prestamo.get('modalidad')}"
    )

    # 5. Fechas de cuotas (sin montos)
    lineas.append("Fechas de cuotas:")
    for c in cuotas:
        lineas.append(f"  - {c['fecha_venc']}")

    # 6. % Interés 1era cuota (sobre capital total)
    if cuotas:
        try:
            capital_total = float(prestamo.get("monto") or 0)
            tasa_num = float(prestamo.get("tasa_interes") or 0)
            interes_primera = capital_total * tasa_num / 100
        except Exception:
            interes_primera = 0.0
        lineas.append(
            f"Interés a pagar, primera cuota: {interes_primera:,.2f}"
        )

    text = "\n".join(lineas)

    # Para compatibilidad, usamos el mismo texto como HTML sencillo
    html = "<pre style='font-family:system-ui,Arial;line-height:1.4'>" + text + "</pre>"

    return subject, html, text

# ------------------ API pública ------------------

def send_loan_created_email(prestamo_id: int) -> None:
    """
    Envía correo de préstamo creado al email del cliente (si existe).
    Controlado por EMAIL_ON_LOAN_CREATED=true/false.
    """
    if os.getenv("EMAIL_ON_LOAN_CREATED", "true").lower() not in ("1", "true", "yes", "on"):
        log.info("EMAIL_ON_LOAN_CREATED desactivado; omito envío.")
        return
    try:
        cliente, prestamo, cuotas = _fetch_loan_bundle(prestamo_id)
        if not cliente or not prestamo:
            log.warning("Datos incompletos para envío (prestamo_id=%s).", prestamo_id)
            return
        email = (cliente.get("email") or "").strip()
        if not email:
            log.info("Cliente sin email; omito envío (prestamo_id=%s).", prestamo_id)
            return
        subject, html, text = _render_loan_created(cliente, prestamo, cuotas)
        _send_email([email], subject, html, text)
    except Exception as e:
        log.exception("Error inesperado enviando email de 'préstamo creado' (id=%s): %s", prestamo_id, e)

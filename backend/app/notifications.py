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
    folio = f"P-{prestamo['id']:04d}"
    subject = f"Nuevo préstamo {folio} — {cliente.get('nombre','')}"

    def _f(v):
        try: return float(v or 0)
        except Exception: return 0.0

    # Totales
    sum_cap = sum(_f(c.get("capital")) for c in cuotas)
    sum_int = sum(_f(c.get("interes")) for c in cuotas)
    sum_tot = 0.0
    for c in cuotas:
        t = c.get("total")
        sum_tot += _f(t) if t is not None else (_f(c.get("capital")) + _f(c.get("interes")))

    # Texto plano (ocultando código del cliente)
    text_lines = [
        f"Préstamo {folio}",
        f"Cliente: {cliente.get('nombre','')}",
        f"Monto: {_fmt_money(prestamo.get('monto'))}",
        f"Tasa: {prestamo.get('tasa_interes')}%  Plazo: {prestamo.get('num_cuotas')}  Inicio: {prestamo.get('fecha_inicio')}",
        "",
        "Cuotas:",
    ]
    for c in cuotas:
        total_fila = (_f(c.get("total")) if c.get("total") is not None
                      else (_f(c.get("capital")) + _f(c.get("interes"))))
        text_lines.append(
            f"#{int(c['numero']):>2}  vence {c['fecha_venc']}: "
            f"capital {_fmt_money(c.get('capital'))} "
            f"interés {_fmt_money(c.get('interes'))} "
            f"total {_fmt_money(total_fila)}"
        )
    text_lines.append("")
    text_lines.append(f"Σ Capital: {_fmt_money(sum_cap)}   Σ Interés: {_fmt_money(sum_int)}   Σ Total: {_fmt_money(sum_tot)}")
    text = "\n".join(text_lines)

    # Filas HTML
    filas = "\n".join(
        (
            lambda total_fila:
            f"<tr>"
            f"<td style='padding:4px;text-align:center'>{int(c['numero'])}</td>"
            f"<td style='padding:4px'>{c['fecha_venc']}</td>"
            f"<td style='padding:4px;text-align:right'>{_fmt_money(c.get('capital'))}</td>"
            f"<td style='padding:4px;text-align:right'>{_fmt_money(c.get('interes'))}</td>"
            f"<td style='padding:4px;text-align:right'><b>{_fmt_money(total_fila)}</b></td>"
            f"</tr>"
        )(
            _f(c.get("total")) if c.get("total") is not None else (_f(c.get("capital")) + _f(c.get("interes")))
        )
        for c in cuotas
    )

    # Fila de totales
    fila_totales = (
        "<tr style='background:#fafafa'>"
        "<td style='padding:6px 8px;text-align:center' colspan='2'><b>Totales</b></td>"
        f"<td style='padding:6px 8px;text-align:right'><b>{_fmt_money(sum_cap)}</b></td>"
        f"<td style='padding:6px 8px;text-align:right'><b>{_fmt_money(sum_int)}</b></td>"
        f"<td style='padding:6px 8px;text-align:right'><b>{_fmt_money(sum_tot)}</b></td>"
        "</tr>"
    )

    # HTML (ocultando código, mostrando folio)
    html = f"""
    <div style="font-family:system-ui,Arial;line-height:1.35">
      <h2 style="margin:0 0 8px 0">Préstamo {folio}</h2>
      <p style="margin:0 0 4px 0"><b>Cliente:</b> {cliente.get('nombre','')}</p>
      <p style="margin:0 0 12px 0">
        <b>Monto:</b> {_fmt_money(prestamo.get('monto'))} &nbsp;·&nbsp;
        <b>Tasa:</b> {prestamo.get('tasa_interes')}% &nbsp;·&nbsp;
        <b>Plazo:</b> {prestamo.get('num_cuotas')} &nbsp;·&nbsp;
        <b>Inicio:</b> {prestamo.get('fecha_inicio')}
      </p>
      <table border="1" cellspacing="0" cellpadding="0" style="border-collapse:collapse">
        <thead style="background:#f5f5f5">
          <tr>
            <th style='padding:6px 8px'>#</th>
            <th style='padding:6px 8px'>Vence</th>
            <th style='padding:6px 8px'>Capital</th>
            <th style='padding:6px 8px'>Interés</th>
            <th style='padding:6px 8px'>Total</th>
          </tr>
        </thead>
        <tbody>
          {filas}
          {fila_totales}
        </tbody>
      </table>
    </div>
    """
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

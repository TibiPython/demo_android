import os, smtplib
from email.message import EmailMessage

host = os.getenv("SMTP_HOST", "smtp.gmail.com")
user = os.getenv("SMTP_USER")
pwd  = os.getenv("SMTP_PASS")
from_addr = os.getenv("SMTP_FROM") or user
to_addr   = os.getenv("SMTP_FROM") or user

print("Probando SMTP a", host, "puerto 587 como", user)

def send_starttls():
    with smtplib.SMTP(host, 587, timeout=20) as s:
        s.ehlo(); s.starttls(); s.ehlo()
        if user: s.login(user, pwd)
        msg = EmailMessage()
        msg["From"] = from_addr
        msg["To"]   = to_addr
        msg["Subject"] = "Prueba SMTP STARTTLS"
        msg.set_content("Esto es una prueba con STARTTLS (587).")
        s.send_message(msg)

def send_ssl():
    with smtplib.SMTP_SSL(host, 465, timeout=20) as s:
        if user: s.login(user, pwd)
        msg = EmailMessage()
        msg["From"] = from_addr
        msg["To"]   = to_addr
        msg["Subject"] = "Prueba SMTP SSL"
        msg.set_content("Esto es una prueba con SSL (465).")
        s.send_message(msg)

try:
    send_starttls()
    print("OK: enviado por 587 (STARTTLS). Revisa tu bandeja.")
except Exception as e1:
    print("Fallo 587:", e1)
    print("Intentando 465/SSL...")
    try:
        send_ssl()
        print("OK: enviado por 465 (SSL). Revisa tu bandeja.")
    except Exception as e2:
        print("Fallo 465 también:", e2)
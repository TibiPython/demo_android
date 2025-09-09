from pathlib import Path
from dotenv import load_dotenv
import os, smtplib, ssl
from email.mime.text import MIMEText

ENV = Path(__file__).resolve().parent / ".env"   # este script lo ejecutas en backend/
load_dotenv(ENV, override=True)

user = os.getenv("SMTP_USER"); pwd = os.getenv("SMTP_PASS")
msg = MIMEText("Prueba directa desde Gmail SMTP (DemoAndroid)")
msg["Subject"] = "Prueba directa SMTP"
msg["From"] = user
msg["To"] = "edwirtibidor@gmail.com"

s = smtplib.SMTP("smtp.gmail.com", 587, timeout=20)
s.starttls(context=ssl.create_default_context())
s.login(user, pwd)
s.sendmail(user, ["edwirtibidor@gmail.com"], msg.as_string())
s.quit()
print("OK enviado (directo)")

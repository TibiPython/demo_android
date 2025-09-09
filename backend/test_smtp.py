import smtplib
from email.mime.text import MIMEText

msg = MIMEText("Prueba SMTP mínima")
msg["Subject"] = "Prueba directa SMTP"
msg["From"] = "no-reply@tu-dominio.com"
msg["To"] = "edwirtibidor@gmail.com"

s = smtplib.SMTP("127.0.0.1", 2525, timeout=10)
s.sendmail(msg["From"], [msg["To"]], msg.as_string())
s.quit()
print("OK enviado")

import smtplib, ssl
user = "edwirtibidor@gmail.com"      # <- tu correo real
pwd  = "btaeryxrpksowfle"  # <- 16 caracteres, sin espacios

s = smtplib.SMTP("smtp.gmail.com", 587, timeout=20)
s.starttls(context=ssl.create_default_context())
s.login(user, pwd)
print("LOGIN OK (587 STARTTLS)")
s.quit()

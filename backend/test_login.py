import smtplib, ssl
user = "tu_cuenta@gmail.com"
pwd  = "abcdefghijklmnop"  # App Password sin espacios

s = smtplib.SMTP("smtp.gmail.com", 587, timeout=15)
s.starttls(context=ssl.create_default_context())
s.login(user, pwd)
print("LOGIN OK")
s.quit()

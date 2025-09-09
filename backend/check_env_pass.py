from dotenv import load_dotenv; load_dotenv()
import os
pwd = os.getenv("SMTP_PASS")
print("LEN:", len(pwd), "VALUE (repr):", repr(pwd))

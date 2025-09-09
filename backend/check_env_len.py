from pathlib import Path
from dotenv import load_dotenv, dotenv_values
import os
ENV_PATH = Path(__file__).resolve().parents[0] / ".env"  # <- si ejecutas este script en backend, usa parents[0]
load_dotenv(dotenv_path=ENV_PATH, override=True)
print("exists:", ENV_PATH.exists())
print("os.getenv LEN:", len(os.getenv("SMTP_PASS","")))
print("dotenv_values LEN:", len(dotenv_values(ENV_PATH).get("SMTP_PASS","")))

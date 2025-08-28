from typing import Dict, Any
import sqlite3

def get_schema_snapshot(conn: sqlite3.Connection) -> Dict[str, Any]:
    cur = conn.cursor()
    tables = [r[0] for r in cur.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name;"
    ).fetchall()]
    schema = {}
    for t in tables:
        cols = [dict(zip([d[0] for d in cur.description], row))
                for row in conn.execute(f"PRAGMA table_info({t});").fetchall()]
        fks = [dict(zip([d[0] for d in cur.description], row))
               for row in conn.execute(f"PRAGMA foreign_key_list({t});").fetchall()]
        schema[t] = {"columns": cols, "foreign_keys": fks}
    return {"tables": schema}

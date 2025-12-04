# DB init script (run once)
import sqlite3, os
DB_PATH = os.environ.get("DICT_DB_PATH", "dictionary.db")
if os.path.exists(DB_PATH):
    print("DB already exists:", DB_PATH)
else:
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("""
    CREATE TABLE dict (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      surface TEXT,
      lemma TEXT,
      pos TEXT,
      translation_ja TEXT,
      example_ko TEXT,
      example_ja TEXT,
      tags TEXT
    )
    """)
    conn.commit()
    conn.close()
    print("DB created at", DB_PATH)

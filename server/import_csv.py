# CSV import: place CSV in server/dict_csv/dict.csv and run inside container
import csv, sqlite3, os
DB_PATH = os.environ.get("DICT_DB_PATH", "dictionary.db")
CSV_PATH = os.environ.get("DICT_CSV", "dict_csv/dict.csv")
if not os.path.exists(DB_PATH):
    print("DB not found. Run init_db.py first.")
    raise SystemExit(1)
conn = sqlite3.connect(DB_PATH)
cur = conn.cursor()
with open(CSV_PATH, encoding='utf-8') as f:
    r = csv.DictReader(f)
    count = 0
    for row in r:
        surface = row.get("surface") or row.get("word")
        lemma = row.get("lemma") or surface
        pos = row.get("pos", "")
        translation_ja = row.get("translation_ja", "")
        example_ko = row.get("example_ko", "")
        example_ja = row.get("example_ja", "")
        tags = row.get("tags", "")
        cur.execute("INSERT INTO dict (surface, lemma, pos, translation_ja, example_ko, example_ja, tags) VALUES (?, ?, ?, ?, ?, ?, ?)",
                    (surface, lemma, pos, translation_ja, example_ko, example_ja, tags))
        count += 1
conn.commit()
conn.close()
print("Imported", count, "rows from", CSV_PATH)

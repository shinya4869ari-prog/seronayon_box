# Minimal FastAPI server: tokenize / lookup / search / sync_cards / cards
from fastapi import FastAPI, HTTPException, Header, Query
from pydantic import BaseModel
import sqlite3, os, json, time, re

DB_PATH = os.environ.get("DICT_DB_PATH", "dictionary.db")
API_TOKEN = os.environ.get("LOCAL_API_TOKEN", "")

app = FastAPI(title="Honyakun Local Dictionary API (local-only)")

def get_conn():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def check_token(x_api_key: str | None = Header(default=None)):
    if API_TOKEN:
        if not x_api_key or x_api_key != API_TOKEN:
            raise HTTPException(status_code=401, detail="Invalid API key")

@app.get("/health")
def health():
    return {"status":"ok","time": time.time()}

class TokenizeRequest(BaseModel):
    text: str

@app.post("/tokenize")
def tokenize(req: TokenizeRequest, x_api_key: str | None = Header(default=None)):
    check_token(x_api_key)
    text = req.text.strip()
    if not text:
        raise HTTPException(status_code=400, detail="text required")
    parts = [p for p in re.split(r"[ \t\n\r,。.、\.\!?·•/]+", text) if p]
    out = []
    idx = 0
    for p in parts:
        start = text.find(p, idx)
        end = start + len(p)
        idx = end
        out.append({"text": p, "pos": "", "start": start, "end": end})
    return {"tokens": out, "engine": "naive_split"}

@app.get("/lookup")
def lookup(word: str = Query(...), x_api_key: str | None = Header(default=None)):
    check_token(x_api_key)
    conn = get_conn()
    cur = conn.execute("SELECT surface, lemma, pos, translation_ja, example_ko, example_ja, tags FROM dict WHERE surface = ? COLLATE NOCASE", (word,))
    row = cur.fetchone()
    if not row:
        cur = conn.execute("SELECT surface, lemma, pos, translation_ja, example_ko, example_ja, tags FROM dict WHERE lemma = ? COLLATE NOCASE", (word,))
        row = cur.fetchone()
    if not row:
        conn.close()
        raise HTTPException(status_code=404, detail="not found")
    result = dict(row)
    try:
        result["translation_ja"] = json.loads(result.get("translation_ja") or "null")
    except Exception:
        result["translation_ja"] = result.get("translation_ja")
    conn.close()
    return result

@app.get("/search")
def search(term: str = Query(..., min_length=1), limit: int = 10, x_api_key: str | None = Header(default=None)):
    check_token(x_api_key)
    conn = get_conn()
    like = f"%{term}%"
    cur = conn.execute(
        "SELECT surface, lemma, pos, translation_ja, example_ko, example_ja, tags FROM dict WHERE surface LIKE ? OR lemma LIKE ? OR tags LIKE ? LIMIT ?",
        (like, like, like, limit)
    )
    rows = cur.fetchall()
    out = []
    for r in rows:
        item = dict(r)
        try:
            item["translation_ja"] = json.loads(item.get("translation_ja") or "null")
        except Exception:
            item["translation_ja"] = item.get("translation_ja")
        out.append(item)
    conn.close()
    return {"results": out, "count": len(out)}

class SyncCardsRequest(BaseModel):
    cards: list

@app.post("/sync_cards")
def sync_cards(req: SyncCardsRequest, x_api_key: str | None = Header(default=None)):
    check_token(x_api_key)
    save_path = os.environ.get("CARDS_STORE", "cards_store.jsonl")
    with open(save_path, "a", encoding="utf-8") as f:
        for c in req.cards:
            f.write(json.dumps(c, ensure_ascii=False) + "\n")
    return {"saved": len(req.cards)}

@app.get("/cards")
def list_cards(x_api_key: str | None = Header(default=None)):
    check_token(x_api_key)
    save_path = os.environ.get("CARDS_STORE", "cards_store.jsonl")
    if not os.path.exists(save_path):
        return {"cards": []}
    with open(save_path, "r", encoding="utf-8") as f:
        lines = [json.loads(l) for l in f if l.strip()]
    return {"cards": lines}

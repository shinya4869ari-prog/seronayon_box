#!/bin/bash
set -eu
ROOT="."
# ensure directories
mkdir -p "$ROOT"/server/dict_csv
mkdir -p "$ROOT"/server/data
mkdir -p "$ROOT"/pwa

cat > "$ROOT/README.md" <<'EOF'
# Honyakun — Local auto-translate (EN/KO/JP) for search snippets

軽量なローカル辞書サーバ（FastAPI + SQLite）と PWA クライアントのテンプレです。
目的: 検索スニペットをスマホから送ると即時に言語判定・トークン化・ローカル辞書検索を行い、英語/韓国語/日本語の語彙をさりげなく表示・掘り下げできること。

クイックスタート（サマリ）
1. GitHub に新規公開リポジトリ `seronayon_box` を作成
2. このテンプレを配置してローカルでコミット
3. .env を編集して LOCAL_API_TOKEN を設定（.env はコミットしない）
4. NAS / ローカル環境で docker-compose up -d --build
5. 初期DB作成:
   docker exec -it honyakun_server python /app/init_db.py
6. dict_csv にサンプル/辞書を置き import:
   docker exec -it honyakun_server python /app/import_csv.py
7. スマホは同一LAN または Tailscale 経由で `http://<NAS_IP>:8000` にアクセス

構成
- server/: FastAPI サーバ（辞書 lookup, tokenize, search, card sync）
- pwa/: フロント（PWA 風、スマホ向け）
- docker-compose.yml / .env.sample / LICENSE (MIT)

ライセンス: MIT (LICENSE ファイルあり)
EOF

cat > "$ROOT/LICENSE" <<'EOF'
MIT License

Copyright (c) 2025 shinya4869ari-prog

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF

cat > "$ROOT/.gitignore" <<'EOF'
# Ignore environment file and runtime data
.env
server/data/
EOF

cat > "$ROOT/docker-compose.yml" <<'EOF'
version: "3.8"
services:
  honyakun:
    build: ./server
    container_name: honyakun_server
    restart: unless-stopped
    ports:
      - "8000:8000"
    volumes:
      - ./server/data:/app/data
      - ./server/dict_csv:/app/dict_csv
    env_file:
      - .env
EOF

cat > "$ROOT/.env.sample" <<'EOF'
# Copy to .env and edit (DO NOT COMMIT .env)
DICT_DB_PATH=/app/data/dictionary.db
CARDS_STORE=/app/data/cards_store.jsonl
LOCAL_API_TOKEN=change_this_to_a_strong_token_eg:honyakun_local_ABC123
EOF

cat > "$ROOT/server/Dockerfile" <<'EOF'
FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

ENV PORT=8000
EXPOSE 8000

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
EOF

cat > "$ROOT/server/requirements.txt" <<'EOF'
fastapi==0.95.2
uvicorn[standard]==0.22.0
pydantic==1.10.12
sqlalchemy==1.4.52
python-multipart==0.0.6
EOF

cat > "$ROOT/server/app.py" <<'EOF'
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
EOF

cat > "$ROOT/server/init_db.py" <<'EOF'
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
EOF

cat > "$ROOT/server/import_csv.py" <<'EOF'
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
EOF

cat > "$ROOT/server/dict_csv/ko-ja.sample.csv" <<'EOF'
surface,lemma,pos,translation_ja,example_ko,example_ja,tags
야채볶음,야채볶음,名詞,"[""野菜炒め"",""野菜の炒め物""]","어제 야채볶음을 만들었어.","昨日は野菜炒めを作った。","料理,初級"
볶다,볶다,動詞,"[""炒める"",""炒る""]","양파를 볶다.","玉ねぎを炒める。","料理,動詞"
EOF

cat > "$ROOT/server/dict_csv/en-ja.sample.csv" <<'EOF'
surface,lemma,pos,translation_ja,example_ko,example_ja,tags
vegetables,vegetable,noun,"[""野菜""]","I chopped the vegetables.","私は野菜を刻んだ。","料理,初級"
stir-fry,stir-fry,verb,"[""炒める"",""フライパンで炒める""]","Stir-fry the vegetables on high heat.","強火で野菜を炒めてください。","料理,動詞"
EOF

cat > "$ROOT/pwa/index.html" <<'EOF'
<!doctype html>
<html lang="ja">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1.0" />
  <title>ほんや君 — Local PWA</title>
  <style>body{font-family:system-ui, -apple-system, sans-serif;padding:12px;background:#f7f9fc}textarea{width:100%;min-height:120px}</style>
</head>
<body>
  <h1>ほんや君（Local）</h1>
  <p>検索スニペットを貼って「解析」→ ローカル辞書に照会します。</p>
  <textarea id="text" placeholder="예: 야채볶음 만드는 법 ..."></textarea>
  <div style="margin-top:8px">
    <button id="analyzeBtn">解析</button>
    <button id="saveBtn">カードをローカル保存</button>
  </div>
  <div id="result" style="margin-top:12px"></div>
  <script src="app.autotranslate.js"></script>
</body>
</html>
EOF

cat > "$ROOT/pwa/app.autotranslate.js" <<'EOF'
// Minimal client: uses local server via LOCAL_API_URL and LOCAL_API_TOKEN stored in localStorage
const analyzeBtn = document.getElementById('analyzeBtn');
const textEl = document.getElementById('text');
const resultEl = document.getElementById('result');

const LOCAL_API_URL = localStorage.getItem('LOCAL_API_URL') || 'http://100.x.x.x:8000';
const apiToken = localStorage.getItem('LOCAL_API_TOKEN') || '';

function detectLangHint(text){
  if (/[ㄱ-ㅎㅏ-ㅣ가-힣]/.test(text)) return 'ko';
  if (/[A-Za-z]/.test(text)) return 'en';
  return 'ja';
}

analyzeBtn.onclick = async () => {
  const text = textEl.value.trim();
  if (!text) { alert('スニペットを入力してください'); return; }
  resultEl.innerHTML = '解析中…';
  const hint = detectLangHint(text);
  const tokens = text.split(/[ \t\n\r,。.、\.\!?·•/]+/).filter(Boolean);
  // parallel lookups
  const results = await Promise.all(tokens.map(async t => {
    try {
      const url = `${LOCAL_API_URL}/lookup?word=${encodeURIComponent(t)}`;
      const res = await fetch(url, { headers: { 'x-api-key': apiToken }});
      if (!res.ok) return { text: t, ok:false };
      const data = await res.json();
      return { text: t, ok:true, data };
    } catch (e) { return { text:t, ok:false }; }
  }));
  // render
  let html = `<div><strong>言語推定:</strong> ${hint}</div><div>`;
  results.forEach(r => {
    html += `<div style="margin-top:8px"><strong>${r.text}</strong> — `;
    if (r.ok) {
      const tr = r.data.translation_ja || r.data.translation;
      html += `<span>${Array.isArray(tr) ? tr.join(', ') : tr}</span>`;
    } else html += `<em>辞書なし</em>`;
    html += `</div>`;
  });
  html += `</div>`;
  resultEl.innerHTML = html;
};
EOF

chmod +x "$ROOT/../populate_files.sh" 2>/dev/null || true
echo "Files populated."
ls -l
EOF

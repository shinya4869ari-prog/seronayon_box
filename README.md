
# seronayon_box

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
>>>>>>> 4d2c581 (chore: initial commit - local auto-translate template (MIT))

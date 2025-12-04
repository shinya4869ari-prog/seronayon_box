#!/bin/bash
set -eu
ROOT="seronayon_box"
mkdir -p "$ROOT"/{server/dict_csv,server/data,pwa}
# create placeholder files (edit these and paste contents from chat)
touch "$ROOT"/README.md
touch "$ROOT"/LICENSE
touch "$ROOT"/.gitignore
touch "$ROOT"/docker-compose.yml
touch "$ROOT"/.env.sample
touch "$ROOT"/server/Dockerfile
touch "$ROOT"/server/requirements.txt
touch "$ROOT"/server/app.py
touch "$ROOT"/server/init_db.py
touch "$ROOT"/server/import_csv.py
touch "$ROOT"/server/dict_csv/ko-ja.sample.csv
touch "$ROOT"/server/dict_csv/en-ja.sample.csv
touch "$ROOT"/pwa/index.html
touch "$ROOT"/pwa/app.autotranslate.js
echo "Created project skeleton at ./$ROOT"
echo "Next: open files and paste contents (copy from the chat message with file contents)."

@echo off
set DANAWA_DB_HOST=localhost
set DANAWA_DB_PORT=4306
set DANAWA_DB_USER=root
set DANAWA_DB_PASSWORD=1234
set DANAWA_DB_NAME=DW_db
set GEMINI_API_KEY=

python api\server.py

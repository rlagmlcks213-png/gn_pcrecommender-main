"""
MySQL 연결 확인 + DW_db 데이터베이스 생성 스크립트.

사용법:
    python check_and_setup_db.py

환경변수로 접속 정보를 바꿀 수 있습니다(기본값: localhost:3306, root, 빈 비밀번호):
    $env:DANAWA_DB_HOST = "localhost"
    $env:DANAWA_DB_PORT = "3306"
    $env:DANAWA_DB_USER = "root"
    $env:DANAWA_DB_PASSWORD = "실제비밀번호"
"""
import os
import sys

try:
    import mysql.connector
except ImportError:
    print("mysql-connector-python이 설치 안 되어 있습니다. 먼저 설치해주세요:")
    print("  pip install mysql-connector-python")
    sys.exit(1)

HOST = os.environ.get("DANAWA_DB_HOST", "localhost")
PORT = int(os.environ.get("DANAWA_DB_PORT", "3306"))
USER = os.environ.get("DANAWA_DB_USER", "root")
PASSWORD = os.environ.get("DANAWA_DB_PASSWORD", "")

print(f"접속 시도: {USER}@{HOST}:{PORT}")

try:
    conn = mysql.connector.connect(host=HOST, port=PORT, user=USER, password=PASSWORD)
    print("✅ MySQL 서버 접속 성공")
except mysql.connector.Error as e:
    print(f"❌ 접속 실패: {e}")
    print("\n확인해주세요:")
    print("  1) MySQL 서비스가 켜져 있는지 (Get-Service | Where-Object {$_.Name -like '*mysql*'})")
    print("  2) 포트가 맞는지 (기본 3306, 다를 수 있음)")
    print("  3) 비밀번호가 맞는지 (DANAWA_DB_PASSWORD 환경변수로 지정)")
    sys.exit(1)

cursor = conn.cursor()

# 현재 존재하는 데이터베이스 목록 표시
cursor.execute("SHOW DATABASES")
databases = [row[0] for row in cursor.fetchall()]
print(f"\n현재 존재하는 데이터베이스: {databases}")

if "DW_db" in databases or "dw_db" in [d.lower() for d in databases]:
    print("\n'DW_db'가 이미 있습니다.")
    cursor.execute("SHOW TABLES FROM DW_db")
    tables = [row[0] for row in cursor.fetchall()]
    print(f"안에 있는 테이블({len(tables)}개): {tables}")
else:
    print("\n'DW_db'가 없어서 새로 만듭니다...")
    cursor.execute("CREATE DATABASE DW_db DEFAULT CHARACTER SET utf8mb4")
    print("✅ 'DW_db' 데이터베이스 생성 완료 (아직 테이블은 없는 빈 상태)")

# local_infile 설정 확인 (danawa_only_load.sql 실행에 필요)
cursor.execute("SHOW VARIABLES LIKE 'local_infile'")
local_infile = cursor.fetchone()
print(f"\nlocal_infile 설정: {local_infile[1]}")
if local_infile[1] == "OFF":
    cursor.execute("SET GLOBAL local_infile = 1")
    print("✅ local_infile을 켰습니다 (CSV 로드에 필요)")

cursor.close()
conn.close()
print("\n=== 준비 완료 — 이제 db/load_real_data.py로 실제 데이터를 넣으실 수 있습니다 ===")

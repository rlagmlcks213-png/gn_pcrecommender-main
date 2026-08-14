"""
DB 연결 헬퍼 (MySQL 버전).

*** 변경(실사용자 요청: "SQL 파일을 그대로 가지고 와서 쓸거야") *** SQLite
프로토타입을 폐기하고, neungjichai/Danawa-DB 저장소 스키마를 그대로 따르는
MySQL로 전환했다. db/schema.sql이 그 저장소의 danawa_only_load.sql(최종
테이블) + add_compat_columns.sql을 그대로 이식한 것이고, db/seed_data.sql이
목업 데이터다(실제 크롤링 결과가 아님 — README 참고).

환경변수(크롤러 연동 때 쓰던 것과 동일한 이름 재사용):
  DANAWA_DB_HOST, DANAWA_DB_PORT, DANAWA_DB_USER, DANAWA_DB_PASSWORD
  DANAWA_DB_NAME 기본값은 "DW_db"(저장소 스키마의 실제 DB명).
"""
import os

import mysql.connector
from mysql.connector.pooling import PooledMySQLConnection


def _db_config() -> dict:
    return {
        "host": os.environ.get("DANAWA_DB_HOST", "localhost"),
        "port": int(os.environ.get("DANAWA_DB_PORT", "3306")),
        "user": os.environ.get("DANAWA_DB_USER", "root"),
        "password": os.environ.get("DANAWA_DB_PASSWORD", ""),
        "database": os.environ.get("DANAWA_DB_NAME", "DW_db"),
        "charset": "utf8mb4",
    }


def get_connection():
    """mysql.connector 커넥션을 돌려준다. dict 형태로 행을 받기 위해
    cursor(dictionary=True)를 쓰는 건 호출부(core/algorithm.py)에서 처리."""
    return mysql.connector.connect(**_db_config())


def _split_statements(sql_text: str) -> list[str]:
    """세미콜론 기준으로 SQL 문을 나눈다(주석 줄은 제거).

    *** 수정: 작은따옴표 문자열 리터럴 안의 세미콜론(예: SVG data URI의
    "data:image/svg+xml;base64,...")은 문장 구분자로 취급하면 안 되는데,
    예전의 단순 split(";")은 이걸 구분 못 해서 문법 에러가 났다 — 이제
    작은따옴표 안에 있는지 추적하면서 그 밖의 세미콜론에서만 자른다. """
    lines = [ln for ln in sql_text.splitlines() if not ln.strip().startswith("--")]
    cleaned = "\n".join(lines)

    statements = []
    current = []
    in_string = False
    i = 0
    while i < len(cleaned):
        ch = cleaned[i]
        current.append(ch)
        if ch == "'":
            # 이스케이프된 작은따옴표('')는 문자열이 안 끝난 것으로 처리
            if in_string and i + 1 < len(cleaned) and cleaned[i + 1] == "'":
                current.append(cleaned[i + 1])
                i += 2
                continue
            in_string = not in_string
        elif ch == ";" and not in_string:
            stmt = "".join(current[:-1]).strip()
            if stmt:
                statements.append(stmt)
            current = []
        i += 1
    tail = "".join(current).strip()
    if tail:
        statements.append(tail)
    return statements


def init_db() -> None:
    """schema.sql + seed_data.sql을 실행해 DB를 새로 만든다.
    스키마 자체가 USE DW_db로 시작하므로, 최초 연결은 database 지정 없이 연다.

    *** 수정: mysql-connector-python 최신 버전(26.x)에서 cursor.execute(sql,
    multi=True)가 더 이상 지원되지 않아서(TypeError), 문(statement) 단위로
    나눠 하나씩 실행하는 방식으로 바꿨다. ***
    """
    config = _db_config()
    bootstrap_config = {k: v for k, v in config.items() if k != "database"}
    conn = mysql.connector.connect(**bootstrap_config)
    cursor = conn.cursor()

    schema_path = os.path.join(os.path.dirname(__file__), "schema.sql")
    seed_path = os.path.join(os.path.dirname(__file__), "seed_data.sql")

    for path in (schema_path, seed_path):
        with open(path, encoding="utf-8") as f:
            sql_text = f.read()
        for statement in _split_statements(sql_text):
            cursor.execute(statement)
        conn.commit()
        print(f"실행 완료: {path}")

    cursor.close()
    conn.close()
    print("DB 초기화 완료")


if __name__ == "__main__":
    init_db()

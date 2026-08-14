"""
실제 크롤링 데이터 로더.

mysql CLI(`mysql ... < file.sql`)로 danawa_only_load.sql을 한 번에 실행하면
일부 카테고리(SSD, 메인보드 등)가 문장 파싱 문제로 조용히 0건 처리되는
현상이 확인됐다 — 원인은 명확히 못 밝혔지만, Python(mysql.connector)으로
문장을 하나씩 실행하면 이 문제가 재현되지 않는다. 그래서 이 스크립트를
mysql CLI 대신 사용한다.

사용:
    python db/load_real_data.py <danawa_only_load.sql 경로>

환경변수(db/db.py와 동일):
    DANAWA_DB_HOST, DANAWA_DB_PORT, DANAWA_DB_USER, DANAWA_DB_PASSWORD
"""
import os
import sys
import mysql.connector


def _db_config(include_database: bool = True) -> dict:
    cfg = {
        "host": os.environ.get("DANAWA_DB_HOST", "localhost"),
        "port": int(os.environ.get("DANAWA_DB_PORT", "3306")),
        "user": os.environ.get("DANAWA_DB_USER", "root"),
        "password": os.environ.get("DANAWA_DB_PASSWORD", ""),
        "charset": "utf8mb4",
        "allow_local_infile": True,
    }
    if include_database:
        cfg["database"] = os.environ.get("DANAWA_DB_NAME", "DW_db")
    return cfg


def split_statements(sql_text: str) -> list[str]:
    """세미콜론 기준으로 SQL 문을 나눈다(주석 줄 제거).
    작은따옴표 문자열 리터럴 안의 세미콜론은 구분자로 취급하지 않는다
    (예: data URI, 스펙 원문 텍스트에 세미콜론이 섞여 있을 수 있음)."""
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


def read_sql_file(path: str) -> str:
    """UTF-8 우선 시도, 실패하면 다른 인코딩도 시도한다.
    PowerShell에서 `mysqldump ... > file.sql`처럼 `>` 리다이렉션을 쓰면
    파일이 UTF-8이 아니라 UTF-16으로 저장되는 경우가 흔해서 대비한다."""
    encodings = ["utf-8", "utf-8-sig", "utf-16", "utf-16-le", "cp949"]
    last_error = None
    for enc in encodings:
        try:
            with open(path, encoding=enc) as f:
                return f.read()
        except (UnicodeDecodeError, UnicodeError) as e:
            last_error = e
            continue
    raise ValueError(f"파일 인코딩을 인식하지 못했습니다({path}): {last_error}")


def run_sql_file(cursor, path: str, label: str = "") -> None:
    sql_text = read_sql_file(path)
    statements = split_statements(sql_text)
    print(f"[{label or path}] {len(statements)}개 문장 실행 시작")
    for i, stmt in enumerate(statements):
        try:
            cursor.execute(stmt)
            if cursor.with_rows:
                cursor.fetchall()
        except mysql.connector.Error as e:
            print(f"  ! 문장 {i} 실패: {e}")
            print(f"    {stmt[:150]}")
    print(f"[{label or path}] 완료")


def print_counts(cursor):
    tables = ["cpu_products", "vga_products", "mboard_products", "ram_products",
              "ssd_products", "hdd_products", "cooler_products", "power_products", "case_products"]
    print("\n=== 카테고리별 최종 건수 ===")
    for t in tables:
        try:
            cursor.execute(f"SELECT COUNT(*) FROM {t}")
            print(f"  {t}: {cursor.fetchone()[0]}")
        except mysql.connector.Error as e:
            print(f"  {t}: 조회 실패 ({e})")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("사용법: python db/load_real_data.py <danawa_only_load.sql 경로>")
        sys.exit(1)
    load_sql_path = sys.argv[1]

    bootstrap = mysql.connector.connect(**_db_config(include_database=False))
    bcur = bootstrap.cursor()
    bcur.execute("SET GLOBAL local_infile = 1")
    bcur.close()
    bootstrap.close()

    conn = mysql.connector.connect(**_db_config(include_database=True))
    cursor = conn.cursor()
    cursor.execute("SET SESSION group_concat_max_len = 1000000")

    run_sql_file(cursor, load_sql_path, "danawa_only_load.sql")
    conn.commit()
    print_counts(cursor)

    cursor.close()
    conn.close()

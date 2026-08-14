"""
현재 DB에서 물리 스펙(소켓/폼팩터/치수 등) 컬럼이 얼마나 채워져 있는지 확인.

사용법:
    python check_spec_coverage.py
"""
import os
import mysql.connector

DB_CONFIG = {
    "host": os.environ.get("DANAWA_DB_HOST", "localhost"),
    "port": int(os.environ.get("DANAWA_DB_PORT", "3306")),
    "user": os.environ.get("DANAWA_DB_USER", "root"),
    "password": os.environ.get("DANAWA_DB_PASSWORD", ""),
    "database": os.environ.get("DANAWA_DB_NAME", "DW_db"),
    "charset": "utf8mb4",
}

# (테이블, 컬럼, 사람이 읽을 이름) — algorithm.py의 check_data_readiness와 동일 목록
CHECKS = [
    ("cpu_products", "socket", "CPU 소켓"),
    ("mboard_products", "socket", "메인보드 소켓"),
    ("mboard_products", "form_factor", "메인보드 폼팩터"),
    ("mboard_products", "ram_type", "메인보드 RAM 규격"),
    ("mboard_products", "ram_slot_count", "메인보드 RAM 슬롯 수"),
    ("ram_products", "ram_type", "RAM 규격"),
    ("cooler_products", "support_sockets", "쿨러 지원 소켓"),
    ("cooler_products", "cooler_type", "쿨러 타입(공랭/수랭)"),
    ("cooler_products", "height_mm", "쿨러 높이"),
    ("cooler_products", "radiator_length_mm", "쿨러 라디에이터 길이(수랭용)"),
    ("cooler_products", "tdp_rating_w", "쿨러 TDP 감당치"),
    ("vga_products", "length_mm", "GPU 길이"),
    ("vga_products", "recommended_psu_w", "GPU 권장 전력"),
    ("power_products", "rated_w", "PSU 정격 출력"),
    ("power_products", "form_factor", "PSU 폼팩터"),
    ("case_products", "support_form_factors", "케이스 지원 폼팩터"),
    ("case_products", "max_cooler_height_mm", "케이스 최대 쿨러 높이"),
    ("case_products", "max_vga_length_mm", "케이스 최대 GPU 길이"),
    ("case_products", "support_psu_form_factors", "케이스 지원 PSU 폼팩터"),
]

if __name__ == "__main__":
    conn = mysql.connector.connect(**DB_CONFIG)
    cursor = conn.cursor()

    print(f"{'항목':22s} {'전체':>8s} {'채워짐':>8s} {'비율':>7s}")
    print("-" * 50)
    empty_items = []
    for table, column, label in CHECKS:
        try:
            cursor.execute(f"SELECT COUNT(*), COUNT({column}) FROM {table}")
            total, filled = cursor.fetchone()
        except mysql.connector.Error:
            print(f"{label:22s} {'컬럼 자체가 없음(add_missing_spec_columns.sql 등 실행 필요)':>30s}")
            empty_items.append(label)
            continue
        ratio = f"{filled/total*100:.0f}%" if total else "-"
        marker = "  ← 비어있음" if filled == 0 else ""
        print(f"{label:22s} {total:>8d} {filled:>8d} {ratio:>7s}{marker}")
        if filled == 0:
            empty_items.append(label)

    print()
    if empty_items:
        print(f"완전히 비어있는 항목({len(empty_items)}개): {', '.join(empty_items)}")
    else:
        print("모든 항목에 데이터가 채워져 있습니다 — 견적 생성이 정상 작동해야 합니다.")

    cursor.close()
    conn.close()

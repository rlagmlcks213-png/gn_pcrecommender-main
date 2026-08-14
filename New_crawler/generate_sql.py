# -*- coding: utf-8 -*-
"""
다나와 크롤링 CSV(crawl_data/*.csv) -> MySQL(DW_db) 단일 소스 적재 SQL 생성기

- opendb(buildcores) 의존성 없음. danawa_crawler 크롤링 데이터만 사용.
- 제외 대상: 중고 / 노트북 / 가격비교불가 / 단종 (벌크는 포함)
- RAM: 옵션명에서 "묶음 개수"(예: 32GB(16Gx2) -> 2개)를 파싱해서 저장하고,
       4개 초과(8개 등 서버/워크스테이션용 대용량 키트)는 제외
- MBoard: ram_slot_count 컬럼을 만들어두고, 상세페이지 스펙 스크래퍼
          (spec_scraper.py) 결과가 쌓인 뒤 별도 UPDATE 스크립트로 채움
          (가격 크롤링 CSV 자체에는 슬롯 개수 정보가 없기 때문)

CSV 헤더의 실제 날짜를 그대로 읽어서 SQL에 반영합니다 (날짜 하드코딩 X).
"""
import csv
import os

CSV_DIR = "crawl_data"   # 크롤러 결과 CSV 폴더 (CPU.csv, VGA.csv ...)
# LOAD DATA LOCAL INFILE 에 사용할 경로 (MySQL 서버가 파일을 읽을 수 있는 절대경로로 바꿔서 사용)
LOAD_PATH_PREFIX = "C:/Users/GN/Desktop/Project_File/Danawa-Crawler-master/crawl_data"

SCHEMA_NAME = "DW_db"

# (카테고리 라벨, csv 파일명, 테이블 접두어)
CATEGORIES = [
    ("CPU",     "CPU.csv",     "cpu"),
    ("VGA",     "VGA.csv",     "vga"),
    ("RAM",     "RAM.csv",     "ram"),
    ("SSD",     "SSD.csv",     "ssd"),
    ("HDD",     "HDD.csv",     "hdd"),
    ("MBoard",  "MBoard.csv",  "mboard"),
    ("Cooler",  "Cooler.csv",  "cooler"),
    ("Power",   "Power.csv",   "power"),   # psu
    ("Case",    "Case.csv",    "case"),
    ("Monitor", "Monitor.csv", "monitor"),
]

# 카테고리별 usage_type 분류 규칙 (기존 view_*.sql 의 usage_type 필터와 호환)
USAGE_TYPE_SQL = {
    "cpu": """
        CASE
            WHEN name LIKE '%EPYC%' OR name LIKE '%Xeon%' OR name LIKE '%제온%' THEN 'server'
            WHEN name LIKE '%THREADRIPPER PRO%' OR name LIKE '%스레드리퍼 PRO%' THEN 'workstation'
            ELSE 'consumer'
        END""",
    "vga": """
        CASE
            WHEN name LIKE '%RTX PRO%' OR name LIKE '%Quadro%' OR name LIKE '%Tesla%' THEN 'workstation'
            WHEN name LIKE '%GT 7%' OR name LIKE '%GT 10%' OR name LIKE '%GT730%'
                 OR name LIKE '%GT710%' OR name LIKE '%R5 230%' OR name LIKE '%HD 6%' THEN 'office'
            ELSE 'gaming'
        END""",
    "ram": "'consumer'",
    "ssd": """
        CASE WHEN name LIKE '%서버용%' OR name LIKE '%엔터프라이즈%' THEN 'server' ELSE 'consumer' END""",
    "hdd": """
        CASE WHEN name LIKE '%NAS용%' OR name LIKE '%엔터프라이즈%' OR name LIKE '%서버용%' THEN 'server' ELSE 'consumer' END""",
    "mboard": """
        CASE WHEN name LIKE '%C621%' OR name LIKE '%C622%' OR name LIKE '%SP3%' OR name LIKE '%SP5%'
                  OR name LIKE '%서버용%' THEN 'server' ELSE 'consumer' END""",
    "cooler": "'consumer'",
    "power": """
        CASE WHEN name LIKE '%서버용%' OR name LIKE '%redundant%' THEN 'server' ELSE 'consumer' END""",
    "case": """
        CASE WHEN name LIKE '%랙마운트%' OR name LIKE '%서버케이스%' OR name LIKE '%rack%' THEN 'server' ELSE 'consumer' END""",
    "monitor": "'consumer'",
}

NAME_EXCLUDE_KEYWORDS = ["중고", "노트북", "리퍼", "전시상품"]
OPTION_EXCLUDE_KEYWORDS = ["중고", "리퍼", "전시"]

# ============================================================
# 취급 회사(브랜드) 제한
# - CPU/VGA는 "회사명"이 아니라 "칩 제조사" 기준이라 브랜드 목록이 아니라
#   제외 키워드(EXCLUDE) 방식으로 처리 (나머지는 브랜드명 포함 여부로 판단)
# - 여기 없는 카테고리(monitor 등)는 필터 없이 전체 유지
# ============================================================

# 회사명 기준 취급 브랜드 (name에 이 중 하나라도 포함되면 채택)
BRAND_INCLUDE_KEYWORDS = {
    "mboard": ["MSI", "ASUS", "에이수스"],
    "cooler": ["DEEPCOOL", "딥쿨"],
    "ram":    ["삼성전자", "TeamGroup", "팀그룹"],
    "ssd":    ["삼성전자"],
    "hdd":    ["Western Digital", "WD ", "웬디"],
    "power":  ["마이크로닉스"],
    "case":   ["darkFlash", "다크플래시", "앱코", "ABKO"],
}

# 칩 제조사 기준 제외 키워드 (name에 이 중 하나라도 포함되면 제외)
CHIP_EXCLUDE_KEYWORDS = {
    "cpu": ["AMD", "라이젠", "Ryzen", "스레드리퍼", "Threadripper",
            "EPYC", "라파엘", "그라도"],
    "vga": ["라데온", "Radeon", "RADEON", "인텔 아크", "Intel Arc", " Arc "],
}


def build_company_expr(prefix):
    """products_select_cols 에 들어갈 company 컬럼 CASE 식과,
    최종 상품 판별 WHERE 절에 추가할 브랜드/칩 필터 조건을 함께 반환.
    반환값: (company_expr_sql, extra_where_sql or None)"""
    if prefix in BRAND_INCLUDE_KEYWORDS:
        keywords = BRAND_INCLUDE_KEYWORDS[prefix]
        when_clauses = "\n            ".join(
            f"WHEN s.name LIKE '%{kw}%' THEN '{kw.strip()}'" for kw in keywords
        )
        company_expr = f"CASE\n            {when_clauses}\n            ELSE NULL\n        END"
        filter_sql = " OR ".join(f"s.name LIKE '%{kw}%'" for kw in keywords)
        return company_expr, f"({filter_sql})"
    elif prefix in CHIP_EXCLUDE_KEYWORDS:
        keywords = CHIP_EXCLUDE_KEYWORDS[prefix]
        exclude_sql = " OR ".join(f"s.name LIKE '%{kw}%'" for kw in keywords)
        # CPU->인텔, VGA->NVIDIA 로 회사명(사실상 취급 칩 제조사)을 고정값으로 채움
        fixed_company = "인텔" if prefix == "cpu" else "NVIDIA"
        company_expr = f"'{fixed_company}'"
        return company_expr, f"NOT ({exclude_sql})"
    else:
        return "SUBSTRING_INDEX(s.name, ' ', 1)", None

# RAM 묶음(스틱) 개수가 이 값을 초과하면 제외 (예: 8Gx8 128GB 서버용 키트 등)
RAM_MAX_STICK_COUNT = 4

# RAM 옵션명에서 "(16Gx2)" 같은 표기의 뒤쪽 숫자(묶음 개수)를 뽑는 정규식 조각
# MySQL 8.0 (ICU 정규식) 기준. 예) '32GB(16Gx2)' -> 'x2' 매칭 -> 숫자만 남기면 2
# 괄호(') ' ) 는 정규식에서 이스케이프가 필요해 문자열 처리가 번거로우므로,
# 굳이 괄호까지 매칭하지 않고 'x2' 형태만 잡아도 충분히 안전하게 구분됨 (실측 데이터로 검증 완료)
RAM_KIT_REGEXP = r"[xX][0-9]+"


def read_dates(csv_path):
    with open(csv_path, encoding="utf-8") as f:
        reader = csv.reader(f)
        header = next(reader)
    return header[2:]  # Id, Name 이후가 날짜 컬럼들


def build_category_sql(label, csv_file, prefix):
    csv_path = os.path.join(CSV_DIR, csv_file)
    dates = read_dates(csv_path)
    n = len(dates)
    load_path = f"{LOAD_PATH_PREFIX}/{csv_file}"

    d_cols = ", ".join(f"d{i} TEXT" for i in range(1, n + 1))

    date_values = ",\n".join(f"({i}, '{d.strip()}')" for i, d in enumerate(dates, 1))

    unpivot_selects = "\nUNION ALL ".join(
        f"SELECT id, {i}, d{i} FROM stg_{prefix}" for i in range(1, n + 1)
    )

    name_excl = "\n  AND ".join(f"name NOT LIKE '%{kw}%'" for kw in NAME_EXCLUDE_KEYWORDS)
    # 주의: 이건 "삭제할" 행을 고르는 조건이므로 OR + LIKE 로 만들어야 함.
    # (예전 버전엔 실수로 NOT LIKE...AND 로 만들어서 정상 옵션을 지우고
    #  벌크/중고만 남기는 정반대 버그가 있었음 -> 반드시 LIKE...OR 유지할 것)
    opt_excl = " OR ".join(f"option_name LIKE '%{kw}%'" for kw in OPTION_EXCLUDE_KEYWORDS)
    usage_expr = USAGE_TYPE_SQL[prefix]

    is_ram = (prefix == "ram")
    is_mboard = (prefix == "mboard")
    is_cpu = (prefix == "cpu")

    # RAM 전용: prices_all 테이블에 stick_count 컬럼 추가 + 4개 초과 옵션 제외
    ram_stick_count_col = ",\n    stick_count TINYINT UNSIGNED" if is_ram else ""
    ram_stick_count_select = f"""
    ,
    CASE
        WHEN REGEXP_LIKE(
                 CASE WHEN LOCATE('_', t.token) > 0
                      THEN TRIM(BOTH '_' FROM SUBSTRING(t.token, 1, CHAR_LENGTH(t.token) - CHAR_LENGTH(SUBSTRING_INDEX(t.token, '_', -1)) - 1))
                      ELSE ''
                 END,
                 '{RAM_KIT_REGEXP}'
             )
        THEN CAST(
                 REGEXP_REPLACE(
                     REGEXP_SUBSTR(
                         CASE WHEN LOCATE('_', t.token) > 0
                              THEN TRIM(BOTH '_' FROM SUBSTRING(t.token, 1, CHAR_LENGTH(t.token) - CHAR_LENGTH(SUBSTRING_INDEX(t.token, '_', -1)) - 1))
                              ELSE ''
                         END,
                         '{RAM_KIT_REGEXP}'
                     ),
                     '[^0-9]', ''
                 ) AS UNSIGNED
             )
        ELSE 1
    END AS stick_count""" if is_ram else ""

    ram_stick_filter = f"""
-- RAM 전용: 묶음(스틱) 개수가 {RAM_MAX_STICK_COUNT}개 초과인 옵션 제외 (서버/워크스테이션용 대용량 키트)
DELETE FROM {prefix}_prices_all
WHERE stick_count > {RAM_MAX_STICK_COUNT};
""" if is_ram else ""

    # MBoard 전용: RAM 소켓(슬롯) 개수 컬럼 (가격 크롤링 CSV엔 스펙 정보가 없어 일단 NULL로 생성,
    # spec_scraper.py 로 상세페이지를 긁은 뒤 별도 UPDATE 스크립트로 채움)
    mboard_extra_col = ",\n    ram_slot_count TINYINT UNSIGNED NULL" if is_mboard else ""
    mboard_extra_note = """
-- ※ ram_slot_count(메인보드 RAM 소켓 개수)는 이 CSV(가격 크롤링 데이터)에는 없는 정보입니다.
--    spec_scraper.py --category mboard 로 상세페이지를 긁어 danawa_spec_summary에 쌓은 뒤,
--    아래(파일 하단) mboard_ram_slot_update.sql 을 실행해서 채워주세요.
""" if is_mboard else ""

    # CPU 전용: 내장그래픽 유무 / PBP-MTP(최소-최대 전력) 컬럼 (역시 가격 CSV엔 없는 정보,
    # spec_scraper.py 로 상세페이지 요약정보를 긁은 뒤 cpu_spec_update.sql 로 채움)
    cpu_extra_col = (
        ",\n    has_igpu VARCHAR(10) NULL"
        ",\n    power_min_w SMALLINT UNSIGNED NULL"
        ",\n    power_max_w SMALLINT UNSIGNED NULL"
    ) if is_cpu else ""
    cpu_extra_note = """
-- ※ has_igpu(내장그래픽 유무), power_min_w/power_max_w(PBP-MTP 최소/최대 전력)는
--    이 CSV(가격 크롤링 데이터)에는 없는 정보입니다.
--    spec_scraper.py --category cpu 로 상세페이지 요약정보를 긁어 danawa_spec_summary에 쌓은 뒤,
--    아래(파일 하단) cpu_spec_update.sql 을 실행해서 채워주세요.
""" if is_cpu else ""

    company_expr, company_filter = build_company_expr(prefix)

    products_insert_cols = "product_id, name, company, usage_type"
    products_select_cols = "s.id,\n    s.name,\n    " + company_expr + " AS company,\n    " + usage_expr + " AS usage_type"
    if is_mboard:
        products_insert_cols += ", ram_slot_count"
        products_select_cols += ",\n    NULL AS ram_slot_count"
    if is_cpu:
        products_insert_cols += ", has_igpu, power_min_w, power_max_w"
        products_select_cols += ",\n    NULL AS has_igpu,\n    NULL AS power_min_w,\n    NULL AS power_max_w"

    prices_select_cols = "pp.product_id, pp.crawl_date, pp.option_name, pp.price" + (", pp.stick_count" if is_ram else "")
    prices_insert_cols = "product_id, crawl_date, option_name, price" + (", stick_count" if is_ram else "")

    sql = f"""
-- ============================================================
-- {label}  (crawl_data/{csv_file}, {n}개 일자: {dates[0].strip()} ~ {dates[-1].strip()})
-- ============================================================
{mboard_extra_note}{cpu_extra_note}
-- 1) 원본 CSV 적재 (스테이징)
DROP TABLE IF EXISTS stg_{prefix};
CREATE TABLE stg_{prefix} (
    id     BIGINT UNSIGNED,
    name   VARCHAR(500),
    {d_cols}
);

LOAD DATA LOCAL INFILE '{load_path}'
INTO TABLE stg_{prefix}
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\\n'
IGNORE 1 ROWS;

SELECT '{label} raw rows' AS info, COUNT(*) AS cnt FROM stg_{prefix};

-- 2) 날짜 컬럼(dN) <-> 실제 크롤링 일시 매핑
DROP TABLE IF EXISTS {prefix}_date_map;
CREATE TABLE {prefix}_date_map (
    col_idx INT PRIMARY KEY,
    crawl_date DATETIME
);
INSERT INTO {prefix}_date_map (col_idx, crawl_date) VALUES
{date_values};

-- 3) 세로로 펼치기 (unpivot) : 전체 원본 상품 기준 (제외 여부는 이후 단계에서 판단)
DROP TABLE IF EXISTS {prefix}_unpivot;
CREATE TABLE {prefix}_unpivot (
    product_id BIGINT UNSIGNED,
    col_idx INT,
    cell TEXT
);
INSERT INTO {prefix}_unpivot (product_id, col_idx, cell)
{unpivot_selects};

-- (참고) 일자별로 값이 있는 상품 수. cnt_nonzero가 0이면 그 날짜는 크롤링이
-- 실패해서 통째로 비어있다는 뜻 (실제로 이런 날짜가 있었음: 예- 특정 날짜 전체 결측).
SELECT '{label} 일자별 유효값 개수 (0이면 그 날짜 크롤링 실패)' AS info,
       dm.col_idx, dm.crawl_date,
       COUNT(u.cell) AS cnt_nonzero
FROM {prefix}_date_map dm
LEFT JOIN {prefix}_unpivot u
  ON u.col_idx = dm.col_idx AND u.cell IS NOT NULL AND TRIM(u.cell) NOT IN ('', '0')
GROUP BY dm.col_idx, dm.crawl_date
ORDER BY dm.col_idx;

-- 4) 한 셀에 여러 옵션이 '|'로 들어있는 경우 옵션 단위로 분리
DROP TABLE IF EXISTS {prefix}_tokens;
CREATE TABLE {prefix}_tokens (
    product_id BIGINT UNSIGNED,
    col_idx INT,
    token VARCHAR(500)
);
INSERT INTO {prefix}_tokens (product_id, col_idx, token)
WITH RECURSIVE seq AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM seq WHERE n < 10
)
SELECT u.product_id, u.col_idx,
       TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(u.cell, '|', seq.n), '|', -1)) AS token
FROM {prefix}_unpivot u
JOIN seq
  ON seq.n <= 1 + (LENGTH(u.cell) - LENGTH(REPLACE(u.cell, '|', '')))
WHERE u.cell IS NOT NULL
  AND TRIM(u.cell) NOT IN ('', '0');

-- 5) 옵션명 / 가격 분리 + 벌크·중고(등) 옵션 자체를 가격 데이터에서 제외
--    (숫자가 아닌 값 = '가격비교예정' 등 가격비교 불가 항목은 정규식 조건에서 자동 제외됨)
DROP TABLE IF EXISTS {prefix}_prices_all;
CREATE TABLE {prefix}_prices_all (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT UNSIGNED,
    crawl_date DATETIME,
    option_name VARCHAR(300),
    price INT UNSIGNED{ram_stick_count_col},
    KEY idx_product_date (product_id, crawl_date)
);
INSERT INTO {prefix}_prices_all (product_id, crawl_date, option_name, price{",  stick_count" if is_ram else ""})
SELECT
    t.product_id,
    m.crawl_date,
    CASE WHEN LOCATE('_', t.token) > 0
         THEN TRIM(BOTH '_' FROM SUBSTRING(t.token, 1, CHAR_LENGTH(t.token) - CHAR_LENGTH(SUBSTRING_INDEX(t.token, '_', -1)) - 1))
         ELSE ''
    END AS option_name,
    CAST(REPLACE(SUBSTRING_INDEX(t.token, '_', -1), ',', '') AS UNSIGNED) AS price{ram_stick_count_select}
FROM {prefix}_tokens t
JOIN {prefix}_date_map m ON m.col_idx = t.col_idx
WHERE t.token <> '0'
  AND SUBSTRING_INDEX(t.token, '_', -1) REGEXP '^[0-9,]+$';

DELETE FROM {prefix}_prices_all
WHERE {opt_excl};
{ram_stick_filter}
-- 6) 최종 적재 대상 상품 판별
--    - 상품명에 벌크/중고/노트북/리퍼/전시상품 포함 -> 제외
--    - 벌크·중고(RAM은 4개 초과 묶음도 포함) 옵션을 뺀 뒤에도 "실제 유효 가격이 존재하는
--      가장 최근 크롤링일자"에 유효 가격이 하나도 없으면 가격비교불가/단종 상품으로 보고 제외
--    * 기준일은 date_map의 마지막 컬럼이 아니라 {prefix}_prices_all에서 직접 구함.
--      -> 크롤러가 특정 일자에 실패해서 그 날짜 컬럼이 전부 0/빈값으로 깨져 있어도
--         실제로 데이터가 있는 가장 최근 날짜를 자동으로 기준으로 잡음.
DROP TABLE IF EXISTS {prefix}_products;
CREATE TABLE {prefix}_products (
    product_id BIGINT UNSIGNED PRIMARY KEY,
    name       VARCHAR(500),
    company    VARCHAR(50),
    usage_type VARCHAR(20){mboard_extra_col}{cpu_extra_col}
);
INSERT INTO {prefix}_products ({products_insert_cols})
SELECT
    {products_select_cols}
FROM stg_{prefix} s
WHERE {name_excl}
{("  AND " + company_filter + chr(10)) if company_filter else ""}  AND EXISTS (
        SELECT 1 FROM {prefix}_prices_all pp
        WHERE pp.product_id = s.id
          AND pp.crawl_date = (SELECT MAX(crawl_date) FROM {prefix}_prices_all)
  );

SELECT '{label} products (필터 적용 후)' AS info, COUNT(*) AS cnt FROM {prefix}_products;

-- 7) 최종 가격 테이블: 적재 대상 상품의 가격 이력만 남김
DROP TABLE IF EXISTS {prefix}_prices;
CREATE TABLE {prefix}_prices (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT UNSIGNED,
    crawl_date DATETIME,
    option_name VARCHAR(300),
    price INT UNSIGNED{ram_stick_count_col},
    KEY idx_product_date (product_id, crawl_date)
);
INSERT INTO {prefix}_prices ({prices_insert_cols})
SELECT {prices_select_cols}
FROM {prefix}_prices_all pp
WHERE pp.product_id IN (SELECT product_id FROM {prefix}_products);

SELECT '{label} prices (필터 적용 후)' AS info, COUNT(*) AS cnt FROM {prefix}_prices;

-- 8) 중간 작업 테이블 정리
DROP TABLE IF EXISTS stg_{prefix};
DROP TABLE IF EXISTS {prefix}_unpivot;
DROP TABLE IF EXISTS {prefix}_tokens;
DROP TABLE IF EXISTS {prefix}_prices_all;
DROP TABLE IF EXISTS {prefix}_date_map;
"""
    return sql


MBOARD_RAM_SLOT_UPDATE_SQL = f"""
-- ============================================================
-- (별도 실행) 메인보드 RAM 소켓(슬롯) 개수 채우기
-- 전제조건:
--   1) 위 danawa_only_load.sql 이 먼저 실행되어 mboard_products 가 존재해야 함
--   2) spec_scraper.py --category mboard 를 실행해서 danawa_spec_summary 테이블에
--      메인보드 상세페이지 스펙(요약 한 줄)이 쌓여 있어야 함
--      (가격 크롤링 CSV에는 슬롯 개수 정보가 아예 없기 때문에 상세페이지를 따로 긁어야 합니다)
-- ============================================================
USE {SCHEMA_NAME};

UPDATE mboard_products p
JOIN (
    SELECT product_id,
           MAX(
               CAST(
                   REGEXP_REPLACE(
                       REGEXP_SUBSTR(spec_value, '[0-9]+[[:space:]]*(개|[Ss]lot)'),
                       '[^0-9]', ''
                   ) AS UNSIGNED
               )
           ) AS slots
    FROM danawa_spec_summary
    WHERE category = 'mboard'
      AND (
            spec_key LIKE '%슬롯%' OR spec_key LIKE '%메모리%'
            OR spec_value LIKE '%슬롯%' OR spec_value LIKE '%[Ss]lot%'
          )
      AND REGEXP_SUBSTR(spec_value, '[0-9]+[[:space:]]*(개|[Ss]lot)') IS NOT NULL
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.ram_slot_count = spec.slots;

SELECT 'mboard ram_slot_count 채워진 개수' AS info, COUNT(*) AS cnt
FROM mboard_products WHERE ram_slot_count IS NOT NULL;

-- 위 REGEXP_SUBSTR 패턴이 실제 spec_value 형식과 안 맞아서 0건이면,
-- 아래 쿼리로 실제 저장된 스펙 문구를 먼저 확인한 뒤 패턴을 맞춰서 다시 실행하세요.
-- SELECT spec_key, spec_value FROM danawa_spec_summary WHERE category='mboard' LIMIT 50;
"""


CPU_SPEC_UPDATE_SQL = f"""
-- ============================================================
-- (별도 실행) CPU 내장그래픽 유무 / PBP-MTP(최소-최대 전력) 채우기
-- 전제조건:
--   1) 위 danawa_only_load.sql 이 먼저 실행되어 cpu_products 가 존재해야 함
--   2) spec_scraper.py --category cpu 를 실행해서 danawa_spec_summary 테이블에
--      CPU 상세페이지 요약정보(다나와 meta description의 "요약정보 : ..." 한 줄)가 쌓여 있어야 함
--      예) "인텔(소켓1700)/.../내장그래픽:탑재/.../PBP-MTP: 125-253W/..."
--          "AMD(소켓AM5)/.../내장그래픽:탑재/.../TDP: 65W/PPT: 88W/..."
--   * 인텔은 PBP-MTP 하나에 "최소-최대W" 형태로, AMD는 TDP(최소)/PPT(최대)로 따로 표기되는
--     경우가 있어서 두 패턴을 모두 처리하도록 만들었습니다.
-- ============================================================
USE {SCHEMA_NAME};

-- 1) 내장그래픽 유무
UPDATE cpu_products p
JOIN (
    SELECT product_id,
           CASE
               WHEN MAX(CASE WHEN spec_value LIKE '%미탑재%' THEN 1 ELSE 0 END) = 1 THEN 'N'
               WHEN MAX(CASE WHEN spec_value LIKE '%탑재%' THEN 1 ELSE 0 END) = 1 THEN 'Y'
               ELSE NULL
           END AS igpu
    FROM danawa_spec_summary
    WHERE category = 'cpu'
      AND spec_key LIKE '%내장그래픽%'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.has_igpu = spec.igpu;

-- 2) 전력(PBP-MTP 방식: 인텔 "125-253W" 형태 -> 최소/최대 분리)
UPDATE cpu_products p
JOIN (
    SELECT product_id,
           CAST(SUBSTRING_INDEX(REGEXP_REPLACE(spec_value, '[^0-9-]', ''), '-', 1) AS UNSIGNED) AS pmin,
           CAST(SUBSTRING_INDEX(REGEXP_REPLACE(spec_value, '[^0-9-]', ''), '-', -1) AS UNSIGNED) AS pmax
    FROM danawa_spec_summary
    WHERE category = 'cpu'
      AND spec_key LIKE '%PBP%'
      AND spec_value REGEXP '^[0-9]+[[:space:]]*-[[:space:]]*[0-9]+'
) spec ON spec.product_id = p.product_id
SET p.power_min_w = spec.pmin,
    p.power_max_w = spec.pmax
WHERE p.power_min_w IS NULL;

-- 3) 전력(AMD 방식: TDP=최소, PPT=최대 가 별도 항목으로 표기되는 경우)
UPDATE cpu_products p
JOIN (
    SELECT t.product_id,
           CAST(REGEXP_REPLACE(t.spec_value, '[^0-9]', '') AS UNSIGNED) AS tdp,
           CAST(REGEXP_REPLACE(pp.spec_value, '[^0-9]', '') AS UNSIGNED) AS ppt
    FROM danawa_spec_summary t
    JOIN danawa_spec_summary pp
      ON pp.category = 'cpu' AND pp.product_id = t.product_id AND pp.spec_key LIKE '%PPT%'
    WHERE t.category = 'cpu'
      AND t.spec_key LIKE '%TDP%'
) spec ON spec.product_id = p.product_id
SET p.power_min_w = spec.tdp,
    p.power_max_w = spec.ppt
WHERE p.power_min_w IS NULL;

SELECT 'cpu has_igpu 채워진 개수' AS info, COUNT(*) AS cnt FROM cpu_products WHERE has_igpu IS NOT NULL;
SELECT 'cpu power_min_w/power_max_w 채워진 개수' AS info, COUNT(*) AS cnt FROM cpu_products WHERE power_min_w IS NOT NULL;

-- 확인용: 실제 저장된 스펙 문구가 위 패턴과 다르면 아래로 먼저 눈으로 확인하세요.
-- SELECT spec_key, spec_value FROM danawa_spec_summary WHERE category='cpu' LIMIT 50;
"""


def main():
    header = f"""-- ============================================================
-- 다나와(danawa) 단일 소스 적재 스크립트 -- 스키마: {SCHEMA_NAME}
-- - buildcores/opendb 의존성 없음 (danawa_crawler 크롤링 데이터만 사용)
-- - 제외 대상: 중고, 노트북, 가격비교불가(가격비교예정 등), 단종(유효 최신일자 가격 없음) -- 벌크는 포함(적재)
-- - RAM: 묶음(스틱) 개수를 파싱해서 저장, {RAM_MAX_STICK_COUNT}개 초과 옵션은 제외
-- - MBoard: ram_slot_count 컬럼 준비 (실제 값은 spec_scraper.py 실행 후 별도 UPDATE로 채움)
-- - CPU: has_igpu(내장그래픽 유무), power_min_w/power_max_w(PBP-MTP) 컬럼 준비
--        (실제 값은 spec_scraper.py 실행 후 별도 UPDATE로 채움)
-- - 대상 카테고리: CPU, VGA, RAM, SSD, HDD, MBoard, Cooler, Power(PSU), Case, Monitor
--
-- 실행 전 준비:
--   1) 서버: my.ini/my.cnf [mysqld] 섹션에 local_infile=1 추가 (재부팅 후에도 유지하려면 필수)
--      또는 즉시 적용만 원하면: SET GLOBAL local_infile = 1;
--   2) MySQL Workbench 클라이언트는 LOAD DATA LOCAL INFILE 이 막히는 경우가 많으니,
--      가급적 mysql.exe CLI(`mysql --local-infile=1`)에서 SOURCE 로 실행하는 것을 권장합니다.
--   3) 이 스크립트 상단 LOAD_PATH_PREFIX 가 실제 CSV 위치와 일치하는지 확인
--      (generate_sql.py 의 LOAD_PATH_PREFIX 값을 바꾼 뒤 다시 생성하면 됩니다)
--
-- 이 스크립트는 {SCHEMA_NAME} 스키마를 매번 새로 지우고(DROP) 다시 만듭니다.
-- ============================================================

DROP DATABASE IF EXISTS {SCHEMA_NAME};
CREATE DATABASE {SCHEMA_NAME} DEFAULT CHARACTER SET utf8mb4;
USE {SCHEMA_NAME};
SET SQL_SAFE_UPDATES = 0;
SET SESSION group_concat_max_len = 1000000;
"""
    parts = [header]
    for label, csv_file, prefix in CATEGORIES:
        parts.append(build_category_sql(label, csv_file, prefix))

    out_path = "danawa_only_load.sql"
    with open(out_path, "w", encoding="utf-8") as f:
        f.write("\n".join(parts))
    print(f"생성 완료: {out_path}")

    out_path2 = "mboard_ram_slot_update.sql"
    with open(out_path2, "w", encoding="utf-8") as f:
        f.write(MBOARD_RAM_SLOT_UPDATE_SQL)
    print(f"생성 완료: {out_path2}")

    out_path3 = "cpu_spec_update.sql"
    with open(out_path3, "w", encoding="utf-8") as f:
        f.write(CPU_SPEC_UPDATE_SQL)
    print(f"생성 완료: {out_path3}")


if __name__ == "__main__":
    main()

-- ============================================================
-- 다나와(danawa) 단일 소스 적재 스크립트 -- 스키마: DW_db
-- - buildcores/opendb 의존성 없음 (danawa_crawler 크롤링 데이터만 사용)
-- - 제외 대상: 중고, 노트북, 가격비교불가(가격비교예정 등), 단종(유효 최신일자 가격 없음) -- 벌크는 포함(적재)
-- - RAM: 묶음(스틱) 개수를 파싱해서 저장, 4개 초과 옵션은 제외
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
-- 이 스크립트는 DW_db 스키마를 매번 새로 지우고(DROP) 다시 만듭니다.
-- ============================================================

DROP DATABASE IF EXISTS DW_db;
CREATE DATABASE DW_db DEFAULT CHARACTER SET utf8mb4;
USE DW_db;
SET SQL_SAFE_UPDATES = 0;
SET SESSION group_concat_max_len = 1000000;


-- ============================================================
-- CPU  (crawl_data/CPU.csv, 7개 일자: 2026-08-01 11:50:04 ~ 2026-08-04 10:32:57)
-- ============================================================

-- ※ has_igpu(내장그래픽 유무), power_min_w/power_max_w(PBP-MTP 최소/최대 전력)는
--    이 CSV(가격 크롤링 데이터)에는 없는 정보입니다.
--    spec_scraper.py --category cpu 로 상세페이지 요약정보를 긁어 danawa_spec_summary에 쌓은 뒤,
--    아래(파일 하단) cpu_spec_update.sql 을 실행해서 채워주세요.

-- 1) 원본 CSV 적재 (스테이징)
DROP TABLE IF EXISTS stg_cpu;
CREATE TABLE stg_cpu (
    id     BIGINT UNSIGNED,
    name   VARCHAR(500),
    d1 TEXT, d2 TEXT, d3 TEXT, d4 TEXT, d5 TEXT, d6 TEXT, d7 TEXT
);

LOAD DATA LOCAL INFILE 'Danawa-Crawler-fix/crawl_data/CPU.csv'
INTO TABLE stg_cpu
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SELECT 'CPU raw rows' AS info, COUNT(*) AS cnt FROM stg_cpu;

-- 2) 날짜 컬럼(dN) <-> 실제 크롤링 일시 매핑
DROP TABLE IF EXISTS cpu_date_map;
CREATE TABLE cpu_date_map (
    col_idx INT PRIMARY KEY,
    crawl_date DATETIME
);
INSERT INTO cpu_date_map (col_idx, crawl_date) VALUES
(1, '2026-08-01 11:50:04'),
(2, '2026-08-02 11:49:14'),
(3, '2026-08-03 09:09:17'),
(4, '2026-08-03 09:58:55'),
(5, '2026-08-03 10:27:00'),
(6, '2026-08-03 11:50:33'),
(7, '2026-08-04 10:32:57');

-- 3) 세로로 펼치기 (unpivot) : 전체 원본 상품 기준 (제외 여부는 이후 단계에서 판단)
DROP TABLE IF EXISTS cpu_unpivot;
CREATE TABLE cpu_unpivot (
    product_id BIGINT UNSIGNED,
    col_idx INT,
    cell TEXT
);
INSERT INTO cpu_unpivot (product_id, col_idx, cell)
SELECT id, 1, d1 FROM stg_cpu
UNION ALL SELECT id, 2, d2 FROM stg_cpu
UNION ALL SELECT id, 3, d3 FROM stg_cpu
UNION ALL SELECT id, 4, d4 FROM stg_cpu
UNION ALL SELECT id, 5, d5 FROM stg_cpu
UNION ALL SELECT id, 6, d6 FROM stg_cpu
UNION ALL SELECT id, 7, d7 FROM stg_cpu;

-- (참고) 일자별로 값이 있는 상품 수. cnt_nonzero가 0이면 그 날짜는 크롤링이
-- 실패해서 통째로 비어있다는 뜻 (실제로 이런 날짜가 있었음: 예- 특정 날짜 전체 결측).
SELECT 'CPU 일자별 유효값 개수 (0이면 그 날짜 크롤링 실패)' AS info,
       dm.col_idx, dm.crawl_date,
       COUNT(u.cell) AS cnt_nonzero
FROM cpu_date_map dm
LEFT JOIN cpu_unpivot u
  ON u.col_idx = dm.col_idx AND u.cell IS NOT NULL AND TRIM(u.cell) NOT IN ('', '0')
GROUP BY dm.col_idx, dm.crawl_date
ORDER BY dm.col_idx;

-- 4) 한 셀에 여러 옵션이 '|'로 들어있는 경우 옵션 단위로 분리
DROP TABLE IF EXISTS cpu_tokens;
CREATE TABLE cpu_tokens (
    product_id BIGINT UNSIGNED,
    col_idx INT,
    token VARCHAR(500)
);
INSERT INTO cpu_tokens (product_id, col_idx, token)
WITH RECURSIVE seq AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM seq WHERE n < 10
)
SELECT u.product_id, u.col_idx,
       TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(u.cell, '|', seq.n), '|', -1)) AS token
FROM cpu_unpivot u
JOIN seq
  ON seq.n <= 1 + (LENGTH(u.cell) - LENGTH(REPLACE(u.cell, '|', '')))
WHERE u.cell IS NOT NULL
  AND TRIM(u.cell) NOT IN ('', '0');

-- 5) 옵션명 / 가격 분리 + 벌크·중고(등) 옵션 자체를 가격 데이터에서 제외
--    (숫자가 아닌 값 = '가격비교예정' 등 가격비교 불가 항목은 정규식 조건에서 자동 제외됨)
DROP TABLE IF EXISTS cpu_prices_all;
CREATE TABLE cpu_prices_all (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT UNSIGNED,
    crawl_date DATETIME,
    option_name VARCHAR(300),
    price INT UNSIGNED,
    KEY idx_product_date (product_id, crawl_date)
);
INSERT INTO cpu_prices_all (product_id, crawl_date, option_name, price)
SELECT
    t.product_id,
    m.crawl_date,
    CASE WHEN LOCATE('_', t.token) > 0
         THEN TRIM(BOTH '_' FROM SUBSTRING(t.token, 1, CHAR_LENGTH(t.token) - CHAR_LENGTH(SUBSTRING_INDEX(t.token, '_', -1)) - 1))
         ELSE ''
    END AS option_name,
    CAST(REPLACE(SUBSTRING_INDEX(t.token, '_', -1), ',', '') AS UNSIGNED) AS price
FROM cpu_tokens t
JOIN cpu_date_map m ON m.col_idx = t.col_idx
WHERE t.token <> '0'
  AND SUBSTRING_INDEX(t.token, '_', -1) REGEXP '^[0-9,]+$';

DELETE FROM cpu_prices_all
WHERE option_name LIKE '%중고%' OR option_name LIKE '%리퍼%' OR option_name LIKE '%전시%';

-- 6) 최종 적재 대상 상품 판별
--    - 상품명에 벌크/중고/노트북/리퍼/전시상품 포함 -> 제외
--    - 벌크·중고(RAM은 4개 초과 묶음도 포함) 옵션을 뺀 뒤에도 "실제 유효 가격이 존재하는
--      가장 최근 크롤링일자"에 유효 가격이 하나도 없으면 가격비교불가/단종 상품으로 보고 제외
--    * 기준일은 date_map의 마지막 컬럼이 아니라 cpu_prices_all에서 직접 구함.
--      -> 크롤러가 특정 일자에 실패해서 그 날짜 컬럼이 전부 0/빈값으로 깨져 있어도
--         실제로 데이터가 있는 가장 최근 날짜를 자동으로 기준으로 잡음.
DROP TABLE IF EXISTS cpu_products;
CREATE TABLE cpu_products (
    product_id BIGINT UNSIGNED PRIMARY KEY,
    name       VARCHAR(500),
    company    VARCHAR(50),
    usage_type VARCHAR(20),
    has_igpu VARCHAR(10) NULL,
    power_min_w SMALLINT UNSIGNED NULL,
    power_max_w SMALLINT UNSIGNED NULL
);
INSERT INTO cpu_products (product_id, name, company, usage_type, has_igpu, power_min_w, power_max_w)
SELECT
    s.id,
    s.name,
    '인텔' AS company,
    
        CASE
            WHEN name LIKE '%EPYC%' OR name LIKE '%Xeon%' OR name LIKE '%제온%' THEN 'server'
            WHEN name LIKE '%THREADRIPPER PRO%' OR name LIKE '%스레드리퍼 PRO%' THEN 'workstation'
            ELSE 'consumer'
        END AS usage_type,
    NULL AS has_igpu,
    NULL AS power_min_w,
    NULL AS power_max_w
FROM stg_cpu s
WHERE name NOT LIKE '%중고%'
  AND name NOT LIKE '%노트북%'
  AND name NOT LIKE '%리퍼%'
  AND name NOT LIKE '%전시상품%'
  AND NOT (s.name LIKE '%AMD%' OR s.name LIKE '%라이젠%' OR s.name LIKE '%Ryzen%' OR s.name LIKE '%스레드리퍼%' OR s.name LIKE '%Threadripper%' OR s.name LIKE '%EPYC%' OR s.name LIKE '%라파엘%' OR s.name LIKE '%그라도%')
  AND EXISTS (
        SELECT 1 FROM cpu_prices_all pp
        WHERE pp.product_id = s.id
          AND pp.crawl_date = (SELECT MAX(crawl_date) FROM cpu_prices_all)
  );

SELECT 'CPU products (필터 적용 후)' AS info, COUNT(*) AS cnt FROM cpu_products;

-- 7) 최종 가격 테이블: 적재 대상 상품의 가격 이력만 남김
DROP TABLE IF EXISTS cpu_prices;
CREATE TABLE cpu_prices (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT UNSIGNED,
    crawl_date DATETIME,
    option_name VARCHAR(300),
    price INT UNSIGNED,
    KEY idx_product_date (product_id, crawl_date)
);
INSERT INTO cpu_prices (product_id, crawl_date, option_name, price)
SELECT pp.product_id, pp.crawl_date, pp.option_name, pp.price
FROM cpu_prices_all pp
WHERE pp.product_id IN (SELECT product_id FROM cpu_products);

SELECT 'CPU prices (필터 적용 후)' AS info, COUNT(*) AS cnt FROM cpu_prices;

-- 8) 중간 작업 테이블 정리
DROP TABLE IF EXISTS stg_cpu;
DROP TABLE IF EXISTS cpu_unpivot;
DROP TABLE IF EXISTS cpu_tokens;
DROP TABLE IF EXISTS cpu_prices_all;
DROP TABLE IF EXISTS cpu_date_map;


-- ============================================================
-- VGA  (crawl_data/VGA.csv, 6개 일자: 2026-08-01 11:50:48 ~ 2026-08-04 10:38:53)
-- ============================================================

-- 1) 원본 CSV 적재 (스테이징)
DROP TABLE IF EXISTS stg_vga;
CREATE TABLE stg_vga (
    id     BIGINT UNSIGNED,
    name   VARCHAR(500),
    d1 TEXT, d2 TEXT, d3 TEXT, d4 TEXT, d5 TEXT, d6 TEXT
);

LOAD DATA LOCAL INFILE 'Danawa-Crawler-fix/crawl_data/VGA.csv'
INTO TABLE stg_vga
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SELECT 'VGA raw rows' AS info, COUNT(*) AS cnt FROM stg_vga;

-- 2) 날짜 컬럼(dN) <-> 실제 크롤링 일시 매핑
DROP TABLE IF EXISTS vga_date_map;
CREATE TABLE vga_date_map (
    col_idx INT PRIMARY KEY,
    crawl_date DATETIME
);
INSERT INTO vga_date_map (col_idx, crawl_date) VALUES
(1, '2026-08-01 11:50:48'),
(2, '2026-08-02 11:49:58'),
(3, '2026-08-03 09:09:57'),
(4, '2026-08-03 10:27:40'),
(5, '2026-08-03 11:51:09'),
(6, '2026-08-04 10:38:53');

-- 3) 세로로 펼치기 (unpivot) : 전체 원본 상품 기준 (제외 여부는 이후 단계에서 판단)
DROP TABLE IF EXISTS vga_unpivot;
CREATE TABLE vga_unpivot (
    product_id BIGINT UNSIGNED,
    col_idx INT,
    cell TEXT
);
INSERT INTO vga_unpivot (product_id, col_idx, cell)
SELECT id, 1, d1 FROM stg_vga
UNION ALL SELECT id, 2, d2 FROM stg_vga
UNION ALL SELECT id, 3, d3 FROM stg_vga
UNION ALL SELECT id, 4, d4 FROM stg_vga
UNION ALL SELECT id, 5, d5 FROM stg_vga
UNION ALL SELECT id, 6, d6 FROM stg_vga;

-- (참고) 일자별로 값이 있는 상품 수. cnt_nonzero가 0이면 그 날짜는 크롤링이
-- 실패해서 통째로 비어있다는 뜻 (실제로 이런 날짜가 있었음: 예- 특정 날짜 전체 결측).
SELECT 'VGA 일자별 유효값 개수 (0이면 그 날짜 크롤링 실패)' AS info,
       dm.col_idx, dm.crawl_date,
       COUNT(u.cell) AS cnt_nonzero
FROM vga_date_map dm
LEFT JOIN vga_unpivot u
  ON u.col_idx = dm.col_idx AND u.cell IS NOT NULL AND TRIM(u.cell) NOT IN ('', '0')
GROUP BY dm.col_idx, dm.crawl_date
ORDER BY dm.col_idx;

-- 4) 한 셀에 여러 옵션이 '|'로 들어있는 경우 옵션 단위로 분리
DROP TABLE IF EXISTS vga_tokens;
CREATE TABLE vga_tokens (
    product_id BIGINT UNSIGNED,
    col_idx INT,
    token VARCHAR(500)
);
INSERT INTO vga_tokens (product_id, col_idx, token)
WITH RECURSIVE seq AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM seq WHERE n < 10
)
SELECT u.product_id, u.col_idx,
       TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(u.cell, '|', seq.n), '|', -1)) AS token
FROM vga_unpivot u
JOIN seq
  ON seq.n <= 1 + (LENGTH(u.cell) - LENGTH(REPLACE(u.cell, '|', '')))
WHERE u.cell IS NOT NULL
  AND TRIM(u.cell) NOT IN ('', '0');

-- 5) 옵션명 / 가격 분리 + 벌크·중고(등) 옵션 자체를 가격 데이터에서 제외
--    (숫자가 아닌 값 = '가격비교예정' 등 가격비교 불가 항목은 정규식 조건에서 자동 제외됨)
DROP TABLE IF EXISTS vga_prices_all;
CREATE TABLE vga_prices_all (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT UNSIGNED,
    crawl_date DATETIME,
    option_name VARCHAR(300),
    price INT UNSIGNED,
    KEY idx_product_date (product_id, crawl_date)
);
INSERT INTO vga_prices_all (product_id, crawl_date, option_name, price)
SELECT
    t.product_id,
    m.crawl_date,
    CASE WHEN LOCATE('_', t.token) > 0
         THEN TRIM(BOTH '_' FROM SUBSTRING(t.token, 1, CHAR_LENGTH(t.token) - CHAR_LENGTH(SUBSTRING_INDEX(t.token, '_', -1)) - 1))
         ELSE ''
    END AS option_name,
    CAST(REPLACE(SUBSTRING_INDEX(t.token, '_', -1), ',', '') AS UNSIGNED) AS price
FROM vga_tokens t
JOIN vga_date_map m ON m.col_idx = t.col_idx
WHERE t.token <> '0'
  AND SUBSTRING_INDEX(t.token, '_', -1) REGEXP '^[0-9,]+$';

DELETE FROM vga_prices_all
WHERE option_name LIKE '%중고%' OR option_name LIKE '%리퍼%' OR option_name LIKE '%전시%';

-- 6) 최종 적재 대상 상품 판별
--    - 상품명에 벌크/중고/노트북/리퍼/전시상품 포함 -> 제외
--    - 벌크·중고(RAM은 4개 초과 묶음도 포함) 옵션을 뺀 뒤에도 "실제 유효 가격이 존재하는
--      가장 최근 크롤링일자"에 유효 가격이 하나도 없으면 가격비교불가/단종 상품으로 보고 제외
--    * 기준일은 date_map의 마지막 컬럼이 아니라 vga_prices_all에서 직접 구함.
--      -> 크롤러가 특정 일자에 실패해서 그 날짜 컬럼이 전부 0/빈값으로 깨져 있어도
--         실제로 데이터가 있는 가장 최근 날짜를 자동으로 기준으로 잡음.
DROP TABLE IF EXISTS vga_products;
CREATE TABLE vga_products (
    product_id BIGINT UNSIGNED PRIMARY KEY,
    name       VARCHAR(500),
    company    VARCHAR(50),
    usage_type VARCHAR(20)
);
INSERT INTO vga_products (product_id, name, company, usage_type)
SELECT
    s.id,
    s.name,
    'NVIDIA' AS company,
    
        CASE
            WHEN name LIKE '%RTX PRO%' OR name LIKE '%Quadro%' OR name LIKE '%Tesla%' THEN 'workstation'
            WHEN name LIKE '%GT 7%' OR name LIKE '%GT 10%' OR name LIKE '%GT730%'
                 OR name LIKE '%GT710%' OR name LIKE '%R5 230%' OR name LIKE '%HD 6%' THEN 'office'
            ELSE 'gaming'
        END AS usage_type
FROM stg_vga s
WHERE name NOT LIKE '%중고%'
  AND name NOT LIKE '%노트북%'
  AND name NOT LIKE '%리퍼%'
  AND name NOT LIKE '%전시상품%'
  AND NOT (s.name LIKE '%라데온%' OR s.name LIKE '%Radeon%' OR s.name LIKE '%RADEON%' OR s.name LIKE '%인텔 아크%' OR s.name LIKE '%Intel Arc%' OR s.name LIKE '% Arc %')
  AND EXISTS (
        SELECT 1 FROM vga_prices_all pp
        WHERE pp.product_id = s.id
          AND pp.crawl_date = (SELECT MAX(crawl_date) FROM vga_prices_all)
  );

SELECT 'VGA products (필터 적용 후)' AS info, COUNT(*) AS cnt FROM vga_products;

-- 7) 최종 가격 테이블: 적재 대상 상품의 가격 이력만 남김
DROP TABLE IF EXISTS vga_prices;
CREATE TABLE vga_prices (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT UNSIGNED,
    crawl_date DATETIME,
    option_name VARCHAR(300),
    price INT UNSIGNED,
    KEY idx_product_date (product_id, crawl_date)
);
INSERT INTO vga_prices (product_id, crawl_date, option_name, price)
SELECT pp.product_id, pp.crawl_date, pp.option_name, pp.price
FROM vga_prices_all pp
WHERE pp.product_id IN (SELECT product_id FROM vga_products);

SELECT 'VGA prices (필터 적용 후)' AS info, COUNT(*) AS cnt FROM vga_prices;

-- 8) 중간 작업 테이블 정리
DROP TABLE IF EXISTS stg_vga;
DROP TABLE IF EXISTS vga_unpivot;
DROP TABLE IF EXISTS vga_tokens;
DROP TABLE IF EXISTS vga_prices_all;
DROP TABLE IF EXISTS vga_date_map;


-- ============================================================
-- RAM  (crawl_data/RAM.csv, 6개 일자: 2026-08-01 11:50:30 ~ 2026-08-04 10:35:24)
-- ============================================================

-- 1) 원본 CSV 적재 (스테이징)
DROP TABLE IF EXISTS stg_ram;
CREATE TABLE stg_ram (
    id     BIGINT UNSIGNED,
    name   VARCHAR(500),
    d1 TEXT, d2 TEXT, d3 TEXT, d4 TEXT, d5 TEXT, d6 TEXT
);

LOAD DATA LOCAL INFILE 'Danawa-Crawler-fix/crawl_data/RAM.csv'
INTO TABLE stg_ram
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SELECT 'RAM raw rows' AS info, COUNT(*) AS cnt FROM stg_ram;

-- 2) 날짜 컬럼(dN) <-> 실제 크롤링 일시 매핑
DROP TABLE IF EXISTS ram_date_map;
CREATE TABLE ram_date_map (
    col_idx INT PRIMARY KEY,
    crawl_date DATETIME
);
INSERT INTO ram_date_map (col_idx, crawl_date) VALUES
(1, '2026-08-01 11:50:30'),
(2, '2026-08-02 11:49:40'),
(3, '2026-08-03 09:09:42'),
(4, '2026-08-03 10:27:21'),
(5, '2026-08-03 11:50:53'),
(6, '2026-08-04 10:35:24');

-- 3) 세로로 펼치기 (unpivot) : 전체 원본 상품 기준 (제외 여부는 이후 단계에서 판단)
DROP TABLE IF EXISTS ram_unpivot;
CREATE TABLE ram_unpivot (
    product_id BIGINT UNSIGNED,
    col_idx INT,
    cell TEXT
);
INSERT INTO ram_unpivot (product_id, col_idx, cell)
SELECT id, 1, d1 FROM stg_ram
UNION ALL SELECT id, 2, d2 FROM stg_ram
UNION ALL SELECT id, 3, d3 FROM stg_ram
UNION ALL SELECT id, 4, d4 FROM stg_ram
UNION ALL SELECT id, 5, d5 FROM stg_ram
UNION ALL SELECT id, 6, d6 FROM stg_ram;

-- (참고) 일자별로 값이 있는 상품 수. cnt_nonzero가 0이면 그 날짜는 크롤링이
-- 실패해서 통째로 비어있다는 뜻 (실제로 이런 날짜가 있었음: 예- 특정 날짜 전체 결측).
SELECT 'RAM 일자별 유효값 개수 (0이면 그 날짜 크롤링 실패)' AS info,
       dm.col_idx, dm.crawl_date,
       COUNT(u.cell) AS cnt_nonzero
FROM ram_date_map dm
LEFT JOIN ram_unpivot u
  ON u.col_idx = dm.col_idx AND u.cell IS NOT NULL AND TRIM(u.cell) NOT IN ('', '0')
GROUP BY dm.col_idx, dm.crawl_date
ORDER BY dm.col_idx;

-- 4) 한 셀에 여러 옵션이 '|'로 들어있는 경우 옵션 단위로 분리
DROP TABLE IF EXISTS ram_tokens;
CREATE TABLE ram_tokens (
    product_id BIGINT UNSIGNED,
    col_idx INT,
    token VARCHAR(500)
);
INSERT INTO ram_tokens (product_id, col_idx, token)
WITH RECURSIVE seq AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM seq WHERE n < 10
)
SELECT u.product_id, u.col_idx,
       TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(u.cell, '|', seq.n), '|', -1)) AS token
FROM ram_unpivot u
JOIN seq
  ON seq.n <= 1 + (LENGTH(u.cell) - LENGTH(REPLACE(u.cell, '|', '')))
WHERE u.cell IS NOT NULL
  AND TRIM(u.cell) NOT IN ('', '0');

-- 5) 옵션명 / 가격 분리 + 벌크·중고(등) 옵션 자체를 가격 데이터에서 제외
--    (숫자가 아닌 값 = '가격비교예정' 등 가격비교 불가 항목은 정규식 조건에서 자동 제외됨)
DROP TABLE IF EXISTS ram_prices_all;
CREATE TABLE ram_prices_all (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT UNSIGNED,
    crawl_date DATETIME,
    option_name VARCHAR(300),
    price INT UNSIGNED,
    stick_count TINYINT UNSIGNED,
    KEY idx_product_date (product_id, crawl_date)
);
INSERT INTO ram_prices_all (product_id, crawl_date, option_name, price,  stick_count)
SELECT
    t.product_id,
    m.crawl_date,
    CASE WHEN LOCATE('_', t.token) > 0
         THEN TRIM(BOTH '_' FROM SUBSTRING(t.token, 1, CHAR_LENGTH(t.token) - CHAR_LENGTH(SUBSTRING_INDEX(t.token, '_', -1)) - 1))
         ELSE ''
    END AS option_name,
    CAST(REPLACE(SUBSTRING_INDEX(t.token, '_', -1), ',', '') AS UNSIGNED) AS price
    ,
    CASE
        WHEN REGEXP_LIKE(
                 CASE WHEN LOCATE('_', t.token) > 0
                      THEN TRIM(BOTH '_' FROM SUBSTRING(t.token, 1, CHAR_LENGTH(t.token) - CHAR_LENGTH(SUBSTRING_INDEX(t.token, '_', -1)) - 1))
                      ELSE ''
                 END,
                 '[xX][0-9]+'
             )
        THEN CAST(
                 REGEXP_REPLACE(
                     REGEXP_SUBSTR(
                         CASE WHEN LOCATE('_', t.token) > 0
                              THEN TRIM(BOTH '_' FROM SUBSTRING(t.token, 1, CHAR_LENGTH(t.token) - CHAR_LENGTH(SUBSTRING_INDEX(t.token, '_', -1)) - 1))
                              ELSE ''
                         END,
                         '[xX][0-9]+'
                     ),
                     '[^0-9]', ''
                 ) AS UNSIGNED
             )
        ELSE 1
    END AS stick_count
FROM ram_tokens t
JOIN ram_date_map m ON m.col_idx = t.col_idx
WHERE t.token <> '0'
  AND SUBSTRING_INDEX(t.token, '_', -1) REGEXP '^[0-9,]+$';

DELETE FROM ram_prices_all
WHERE option_name LIKE '%중고%' OR option_name LIKE '%리퍼%' OR option_name LIKE '%전시%';

-- RAM 전용: 묶음(스틱) 개수가 4개 초과인 옵션 제외 (서버/워크스테이션용 대용량 키트)
DELETE FROM ram_prices_all
WHERE stick_count > 4;

-- 6) 최종 적재 대상 상품 판별
--    - 상품명에 벌크/중고/노트북/리퍼/전시상품 포함 -> 제외
--    - 벌크·중고(RAM은 4개 초과 묶음도 포함) 옵션을 뺀 뒤에도 "실제 유효 가격이 존재하는
--      가장 최근 크롤링일자"에 유효 가격이 하나도 없으면 가격비교불가/단종 상품으로 보고 제외
--    * 기준일은 date_map의 마지막 컬럼이 아니라 ram_prices_all에서 직접 구함.
--      -> 크롤러가 특정 일자에 실패해서 그 날짜 컬럼이 전부 0/빈값으로 깨져 있어도
--         실제로 데이터가 있는 가장 최근 날짜를 자동으로 기준으로 잡음.
DROP TABLE IF EXISTS ram_products;
CREATE TABLE ram_products (
    product_id BIGINT UNSIGNED PRIMARY KEY,
    name       VARCHAR(500),
    company    VARCHAR(50),
    usage_type VARCHAR(20)
);
INSERT INTO ram_products (product_id, name, company, usage_type)
SELECT
    s.id,
    s.name,
    CASE
            WHEN s.name LIKE '%삼성전자%' THEN '삼성전자'
            WHEN s.name LIKE '%TeamGroup%' THEN 'TeamGroup'
            WHEN s.name LIKE '%팀그룹%' THEN '팀그룹'
            ELSE NULL
        END AS company,
    'consumer' AS usage_type
FROM stg_ram s
WHERE name NOT LIKE '%중고%'
  AND name NOT LIKE '%노트북%'
  AND name NOT LIKE '%리퍼%'
  AND name NOT LIKE '%전시상품%'
  AND (s.name LIKE '%삼성전자%' OR s.name LIKE '%TeamGroup%' OR s.name LIKE '%팀그룹%')
  AND EXISTS (
        SELECT 1 FROM ram_prices_all pp
        WHERE pp.product_id = s.id
          AND pp.crawl_date = (SELECT MAX(crawl_date) FROM ram_prices_all)
  );

SELECT 'RAM products (필터 적용 후)' AS info, COUNT(*) AS cnt FROM ram_products;

-- 7) 최종 가격 테이블: 적재 대상 상품의 가격 이력만 남김
DROP TABLE IF EXISTS ram_prices;
CREATE TABLE ram_prices (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT UNSIGNED,
    crawl_date DATETIME,
    option_name VARCHAR(300),
    price INT UNSIGNED,
    stick_count TINYINT UNSIGNED,
    KEY idx_product_date (product_id, crawl_date)
);
INSERT INTO ram_prices (product_id, crawl_date, option_name, price, stick_count)
SELECT pp.product_id, pp.crawl_date, pp.option_name, pp.price, pp.stick_count
FROM ram_prices_all pp
WHERE pp.product_id IN (SELECT product_id FROM ram_products);

SELECT 'RAM prices (필터 적용 후)' AS info, COUNT(*) AS cnt FROM ram_prices;

-- 8) 중간 작업 테이블 정리
DROP TABLE IF EXISTS stg_ram;
DROP TABLE IF EXISTS ram_unpivot;
DROP TABLE IF EXISTS ram_tokens;
DROP TABLE IF EXISTS ram_prices_all;
DROP TABLE IF EXISTS ram_date_map;


-- ============================================================
-- SSD  (crawl_data/SSD.csv, 6개 일자: 2026-08-01 11:50:25 ~ 2026-08-04 10:36:51)
-- ============================================================

-- 1) 원본 CSV 적재 (스테이징)
DROP TABLE IF EXISTS stg_ssd;
CREATE TABLE stg_ssd (
    id     BIGINT UNSIGNED,
    name   VARCHAR(500),
    d1 TEXT, d2 TEXT, d3 TEXT, d4 TEXT, d5 TEXT, d6 TEXT
);

LOAD DATA LOCAL INFILE 'Danawa-Crawler-fix/crawl_data/SSD.csv'
INTO TABLE stg_ssd
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SELECT 'SSD raw rows' AS info, COUNT(*) AS cnt FROM stg_ssd;

-- 2) 날짜 컬럼(dN) <-> 실제 크롤링 일시 매핑
DROP TABLE IF EXISTS ssd_date_map;
CREATE TABLE ssd_date_map (
    col_idx INT PRIMARY KEY,
    crawl_date DATETIME
);
INSERT INTO ssd_date_map (col_idx, crawl_date) VALUES
(1, '2026-08-01 11:50:25'),
(2, '2026-08-02 11:49:40'),
(3, '2026-08-03 09:09:42'),
(4, '2026-08-03 10:27:25'),
(5, '2026-08-03 11:50:58'),
(6, '2026-08-04 10:36:51');

-- 3) 세로로 펼치기 (unpivot) : 전체 원본 상품 기준 (제외 여부는 이후 단계에서 판단)
DROP TABLE IF EXISTS ssd_unpivot;
CREATE TABLE ssd_unpivot (
    product_id BIGINT UNSIGNED,
    col_idx INT,
    cell TEXT
);
INSERT INTO ssd_unpivot (product_id, col_idx, cell)
SELECT id, 1, d1 FROM stg_ssd
UNION ALL SELECT id, 2, d2 FROM stg_ssd
UNION ALL SELECT id, 3, d3 FROM stg_ssd
UNION ALL SELECT id, 4, d4 FROM stg_ssd
UNION ALL SELECT id, 5, d5 FROM stg_ssd
UNION ALL SELECT id, 6, d6 FROM stg_ssd;

-- (참고) 일자별로 값이 있는 상품 수. cnt_nonzero가 0이면 그 날짜는 크롤링이
-- 실패해서 통째로 비어있다는 뜻 (실제로 이런 날짜가 있었음: 예- 특정 날짜 전체 결측).
SELECT 'SSD 일자별 유효값 개수 (0이면 그 날짜 크롤링 실패)' AS info,
       dm.col_idx, dm.crawl_date,
       COUNT(u.cell) AS cnt_nonzero
FROM ssd_date_map dm
LEFT JOIN ssd_unpivot u
  ON u.col_idx = dm.col_idx AND u.cell IS NOT NULL AND TRIM(u.cell) NOT IN ('', '0')
GROUP BY dm.col_idx, dm.crawl_date
ORDER BY dm.col_idx;

-- 4) 한 셀에 여러 옵션이 '|'로 들어있는 경우 옵션 단위로 분리
DROP TABLE IF EXISTS ssd_tokens;
CREATE TABLE ssd_tokens (
    product_id BIGINT UNSIGNED,
    col_idx INT,
    token VARCHAR(500)
);
INSERT INTO ssd_tokens (product_id, col_idx, token)
WITH RECURSIVE seq AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM seq WHERE n < 10
)
SELECT u.product_id, u.col_idx,
       TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(u.cell, '|', seq.n), '|', -1)) AS token
FROM ssd_unpivot u
JOIN seq
  ON seq.n <= 1 + (LENGTH(u.cell) - LENGTH(REPLACE(u.cell, '|', '')))
WHERE u.cell IS NOT NULL
  AND TRIM(u.cell) NOT IN ('', '0');

-- 5) 옵션명 / 가격 분리 + 벌크·중고(등) 옵션 자체를 가격 데이터에서 제외
--    (숫자가 아닌 값 = '가격비교예정' 등 가격비교 불가 항목은 정규식 조건에서 자동 제외됨)
DROP TABLE IF EXISTS ssd_prices_all;
CREATE TABLE ssd_prices_all (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT UNSIGNED,
    crawl_date DATETIME,
    option_name VARCHAR(300),
    price INT UNSIGNED,
    KEY idx_product_date (product_id, crawl_date)
);
INSERT INTO ssd_prices_all (product_id, crawl_date, option_name, price)
SELECT
    t.product_id,
    m.crawl_date,
    CASE WHEN LOCATE('_', t.token) > 0
         THEN TRIM(BOTH '_' FROM SUBSTRING(t.token, 1, CHAR_LENGTH(t.token) - CHAR_LENGTH(SUBSTRING_INDEX(t.token, '_', -1)) - 1))
         ELSE ''
    END AS option_name,
    CAST(REPLACE(SUBSTRING_INDEX(t.token, '_', -1), ',', '') AS UNSIGNED) AS price
FROM ssd_tokens t
JOIN ssd_date_map m ON m.col_idx = t.col_idx
WHERE t.token <> '0'
  AND SUBSTRING_INDEX(t.token, '_', -1) REGEXP '^[0-9,]+$';

DELETE FROM ssd_prices_all
WHERE option_name LIKE '%중고%' OR option_name LIKE '%리퍼%' OR option_name LIKE '%전시%';

-- 6) 최종 적재 대상 상품 판별
--    - 상품명에 벌크/중고/노트북/리퍼/전시상품 포함 -> 제외
--    - 벌크·중고(RAM은 4개 초과 묶음도 포함) 옵션을 뺀 뒤에도 "실제 유효 가격이 존재하는
--      가장 최근 크롤링일자"에 유효 가격이 하나도 없으면 가격비교불가/단종 상품으로 보고 제외
--    * 기준일은 date_map의 마지막 컬럼이 아니라 ssd_prices_all에서 직접 구함.
--      -> 크롤러가 특정 일자에 실패해서 그 날짜 컬럼이 전부 0/빈값으로 깨져 있어도
--         실제로 데이터가 있는 가장 최근 날짜를 자동으로 기준으로 잡음.
DROP TABLE IF EXISTS ssd_products;
CREATE TABLE ssd_products (
    product_id BIGINT UNSIGNED PRIMARY KEY,
    name       VARCHAR(500),
    company    VARCHAR(50),
    usage_type VARCHAR(20)
);
INSERT INTO ssd_products (product_id, name, company, usage_type)
SELECT
    s.id,
    s.name,
    CASE
            WHEN s.name LIKE '%삼성전자%' THEN '삼성전자'
            ELSE NULL
        END AS company,
    
        CASE WHEN name LIKE '%서버용%' OR name LIKE '%엔터프라이즈%' THEN 'server' ELSE 'consumer' END AS usage_type
FROM stg_ssd s
WHERE name NOT LIKE '%중고%'
  AND name NOT LIKE '%노트북%'
  AND name NOT LIKE '%리퍼%'
  AND name NOT LIKE '%전시상품%'
  AND (s.name LIKE '%삼성전자%')
  AND EXISTS (
        SELECT 1 FROM ssd_prices_all pp
        WHERE pp.product_id = s.id
          AND pp.crawl_date = (SELECT MAX(crawl_date) FROM ssd_prices_all)
  );

SELECT 'SSD products (필터 적용 후)' AS info, COUNT(*) AS cnt FROM ssd_products;

-- 7) 최종 가격 테이블: 적재 대상 상품의 가격 이력만 남김
DROP TABLE IF EXISTS ssd_prices;
CREATE TABLE ssd_prices (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT UNSIGNED,
    crawl_date DATETIME,
    option_name VARCHAR(300),
    price INT UNSIGNED,
    KEY idx_product_date (product_id, crawl_date)
);
INSERT INTO ssd_prices (product_id, crawl_date, option_name, price)
SELECT pp.product_id, pp.crawl_date, pp.option_name, pp.price
FROM ssd_prices_all pp
WHERE pp.product_id IN (SELECT product_id FROM ssd_products);

SELECT 'SSD prices (필터 적용 후)' AS info, COUNT(*) AS cnt FROM ssd_prices;

-- 8) 중간 작업 테이블 정리
DROP TABLE IF EXISTS stg_ssd;
DROP TABLE IF EXISTS ssd_unpivot;
DROP TABLE IF EXISTS ssd_tokens;
DROP TABLE IF EXISTS ssd_prices_all;
DROP TABLE IF EXISTS ssd_date_map;


-- ============================================================
-- HDD  (crawl_data/HDD.csv, 6개 일자: 2026-08-01 11:50:44 ~ 2026-08-04 10:39:30)
-- ============================================================

-- 1) 원본 CSV 적재 (스테이징)
DROP TABLE IF EXISTS stg_hdd;
CREATE TABLE stg_hdd (
    id     BIGINT UNSIGNED,
    name   VARCHAR(500),
    d1 TEXT, d2 TEXT, d3 TEXT, d4 TEXT, d5 TEXT, d6 TEXT
);

LOAD DATA LOCAL INFILE 'Danawa-Crawler-fix/crawl_data/HDD.csv'
INTO TABLE stg_hdd
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SELECT 'HDD raw rows' AS info, COUNT(*) AS cnt FROM stg_hdd;

-- 2) 날짜 컬럼(dN) <-> 실제 크롤링 일시 매핑
DROP TABLE IF EXISTS hdd_date_map;
CREATE TABLE hdd_date_map (
    col_idx INT PRIMARY KEY,
    crawl_date DATETIME
);
INSERT INTO hdd_date_map (col_idx, crawl_date) VALUES
(1, '2026-08-01 11:50:44'),
(2, '2026-08-02 11:49:59'),
(3, '2026-08-03 09:10:08'),
(4, '2026-08-03 10:27:43'),
(5, '2026-08-03 11:51:18'),
(6, '2026-08-04 10:39:30');

-- 3) 세로로 펼치기 (unpivot) : 전체 원본 상품 기준 (제외 여부는 이후 단계에서 판단)
DROP TABLE IF EXISTS hdd_unpivot;
CREATE TABLE hdd_unpivot (
    product_id BIGINT UNSIGNED,
    col_idx INT,
    cell TEXT
);
INSERT INTO hdd_unpivot (product_id, col_idx, cell)
SELECT id, 1, d1 FROM stg_hdd
UNION ALL SELECT id, 2, d2 FROM stg_hdd
UNION ALL SELECT id, 3, d3 FROM stg_hdd
UNION ALL SELECT id, 4, d4 FROM stg_hdd
UNION ALL SELECT id, 5, d5 FROM stg_hdd
UNION ALL SELECT id, 6, d6 FROM stg_hdd;

-- (참고) 일자별로 값이 있는 상품 수. cnt_nonzero가 0이면 그 날짜는 크롤링이
-- 실패해서 통째로 비어있다는 뜻 (실제로 이런 날짜가 있었음: 예- 특정 날짜 전체 결측).
SELECT 'HDD 일자별 유효값 개수 (0이면 그 날짜 크롤링 실패)' AS info,
       dm.col_idx, dm.crawl_date,
       COUNT(u.cell) AS cnt_nonzero
FROM hdd_date_map dm
LEFT JOIN hdd_unpivot u
  ON u.col_idx = dm.col_idx AND u.cell IS NOT NULL AND TRIM(u.cell) NOT IN ('', '0')
GROUP BY dm.col_idx, dm.crawl_date
ORDER BY dm.col_idx;

-- 4) 한 셀에 여러 옵션이 '|'로 들어있는 경우 옵션 단위로 분리
DROP TABLE IF EXISTS hdd_tokens;
CREATE TABLE hdd_tokens (
    product_id BIGINT UNSIGNED,
    col_idx INT,
    token VARCHAR(500)
);
INSERT INTO hdd_tokens (product_id, col_idx, token)
WITH RECURSIVE seq AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM seq WHERE n < 10
)
SELECT u.product_id, u.col_idx,
       TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(u.cell, '|', seq.n), '|', -1)) AS token
FROM hdd_unpivot u
JOIN seq
  ON seq.n <= 1 + (LENGTH(u.cell) - LENGTH(REPLACE(u.cell, '|', '')))
WHERE u.cell IS NOT NULL
  AND TRIM(u.cell) NOT IN ('', '0');

-- 5) 옵션명 / 가격 분리 + 벌크·중고(등) 옵션 자체를 가격 데이터에서 제외
--    (숫자가 아닌 값 = '가격비교예정' 등 가격비교 불가 항목은 정규식 조건에서 자동 제외됨)
DROP TABLE IF EXISTS hdd_prices_all;
CREATE TABLE hdd_prices_all (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT UNSIGNED,
    crawl_date DATETIME,
    option_name VARCHAR(300),
    price INT UNSIGNED,
    KEY idx_product_date (product_id, crawl_date)
);
INSERT INTO hdd_prices_all (product_id, crawl_date, option_name, price)
SELECT
    t.product_id,
    m.crawl_date,
    CASE WHEN LOCATE('_', t.token) > 0
         THEN TRIM(BOTH '_' FROM SUBSTRING(t.token, 1, CHAR_LENGTH(t.token) - CHAR_LENGTH(SUBSTRING_INDEX(t.token, '_', -1)) - 1))
         ELSE ''
    END AS option_name,
    CAST(REPLACE(SUBSTRING_INDEX(t.token, '_', -1), ',', '') AS UNSIGNED) AS price
FROM hdd_tokens t
JOIN hdd_date_map m ON m.col_idx = t.col_idx
WHERE t.token <> '0'
  AND SUBSTRING_INDEX(t.token, '_', -1) REGEXP '^[0-9,]+$';

DELETE FROM hdd_prices_all
WHERE option_name LIKE '%중고%' OR option_name LIKE '%리퍼%' OR option_name LIKE '%전시%';

-- 6) 최종 적재 대상 상품 판별
--    - 상품명에 벌크/중고/노트북/리퍼/전시상품 포함 -> 제외
--    - 벌크·중고(RAM은 4개 초과 묶음도 포함) 옵션을 뺀 뒤에도 "실제 유효 가격이 존재하는
--      가장 최근 크롤링일자"에 유효 가격이 하나도 없으면 가격비교불가/단종 상품으로 보고 제외
--    * 기준일은 date_map의 마지막 컬럼이 아니라 hdd_prices_all에서 직접 구함.
--      -> 크롤러가 특정 일자에 실패해서 그 날짜 컬럼이 전부 0/빈값으로 깨져 있어도
--         실제로 데이터가 있는 가장 최근 날짜를 자동으로 기준으로 잡음.
DROP TABLE IF EXISTS hdd_products;
CREATE TABLE hdd_products (
    product_id BIGINT UNSIGNED PRIMARY KEY,
    name       VARCHAR(500),
    company    VARCHAR(50),
    usage_type VARCHAR(20)
);
INSERT INTO hdd_products (product_id, name, company, usage_type)
SELECT
    s.id,
    s.name,
    CASE
            WHEN s.name LIKE '%Western Digital%' THEN 'Western Digital'
            WHEN s.name LIKE '%WD %' THEN 'WD'
            WHEN s.name LIKE '%웬디%' THEN '웬디'
            ELSE NULL
        END AS company,
    
        CASE WHEN name LIKE '%NAS용%' OR name LIKE '%엔터프라이즈%' OR name LIKE '%서버용%' THEN 'server' ELSE 'consumer' END AS usage_type
FROM stg_hdd s
WHERE name NOT LIKE '%중고%'
  AND name NOT LIKE '%노트북%'
  AND name NOT LIKE '%리퍼%'
  AND name NOT LIKE '%전시상품%'
  AND (s.name LIKE '%Western Digital%' OR s.name LIKE '%WD %' OR s.name LIKE '%웬디%')
  AND EXISTS (
        SELECT 1 FROM hdd_prices_all pp
        WHERE pp.product_id = s.id
          AND pp.crawl_date = (SELECT MAX(crawl_date) FROM hdd_prices_all)
  );

SELECT 'HDD products (필터 적용 후)' AS info, COUNT(*) AS cnt FROM hdd_products;

-- 7) 최종 가격 테이블: 적재 대상 상품의 가격 이력만 남김
DROP TABLE IF EXISTS hdd_prices;
CREATE TABLE hdd_prices (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT UNSIGNED,
    crawl_date DATETIME,
    option_name VARCHAR(300),
    price INT UNSIGNED,
    KEY idx_product_date (product_id, crawl_date)
);
INSERT INTO hdd_prices (product_id, crawl_date, option_name, price)
SELECT pp.product_id, pp.crawl_date, pp.option_name, pp.price
FROM hdd_prices_all pp
WHERE pp.product_id IN (SELECT product_id FROM hdd_products);

SELECT 'HDD prices (필터 적용 후)' AS info, COUNT(*) AS cnt FROM hdd_prices;

-- 8) 중간 작업 테이블 정리
DROP TABLE IF EXISTS stg_hdd;
DROP TABLE IF EXISTS hdd_unpivot;
DROP TABLE IF EXISTS hdd_tokens;
DROP TABLE IF EXISTS hdd_prices_all;
DROP TABLE IF EXISTS hdd_date_map;


-- ============================================================
-- MBoard  (crawl_data/MBoard.csv, 6개 일자: 2026-08-01 11:50:04 ~ 2026-08-04 10:32:57)
-- ============================================================

-- ※ ram_slot_count(메인보드 RAM 소켓 개수)는 이 CSV(가격 크롤링 데이터)에는 없는 정보입니다.
--    spec_scraper.py --category mboard 로 상세페이지를 긁어 danawa_spec_summary에 쌓은 뒤,
--    아래(파일 하단) mboard_ram_slot_update.sql 을 실행해서 채워주세요.

-- 1) 원본 CSV 적재 (스테이징)
DROP TABLE IF EXISTS stg_mboard;
CREATE TABLE stg_mboard (
    id     BIGINT UNSIGNED,
    name   VARCHAR(500),
    d1 TEXT, d2 TEXT, d3 TEXT, d4 TEXT, d5 TEXT, d6 TEXT
);

LOAD DATA LOCAL INFILE 'Danawa-Crawler-fix/crawl_data/MBoard.csv'
INTO TABLE stg_mboard
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SELECT 'MBoard raw rows' AS info, COUNT(*) AS cnt FROM stg_mboard;

-- 2) 날짜 컬럼(dN) <-> 실제 크롤링 일시 매핑
DROP TABLE IF EXISTS mboard_date_map;
CREATE TABLE mboard_date_map (
    col_idx INT PRIMARY KEY,
    crawl_date DATETIME
);
INSERT INTO mboard_date_map (col_idx, crawl_date) VALUES
(1, '2026-08-01 11:50:04'),
(2, '2026-08-02 11:49:14'),
(3, '2026-08-03 09:09:17'),
(4, '2026-08-03 10:27:00'),
(5, '2026-08-03 11:50:33'),
(6, '2026-08-04 10:32:57');

-- 3) 세로로 펼치기 (unpivot) : 전체 원본 상품 기준 (제외 여부는 이후 단계에서 판단)
DROP TABLE IF EXISTS mboard_unpivot;
CREATE TABLE mboard_unpivot (
    product_id BIGINT UNSIGNED,
    col_idx INT,
    cell TEXT
);
INSERT INTO mboard_unpivot (product_id, col_idx, cell)
SELECT id, 1, d1 FROM stg_mboard
UNION ALL SELECT id, 2, d2 FROM stg_mboard
UNION ALL SELECT id, 3, d3 FROM stg_mboard
UNION ALL SELECT id, 4, d4 FROM stg_mboard
UNION ALL SELECT id, 5, d5 FROM stg_mboard
UNION ALL SELECT id, 6, d6 FROM stg_mboard;

-- (참고) 일자별로 값이 있는 상품 수. cnt_nonzero가 0이면 그 날짜는 크롤링이
-- 실패해서 통째로 비어있다는 뜻 (실제로 이런 날짜가 있었음: 예- 특정 날짜 전체 결측).
SELECT 'MBoard 일자별 유효값 개수 (0이면 그 날짜 크롤링 실패)' AS info,
       dm.col_idx, dm.crawl_date,
       COUNT(u.cell) AS cnt_nonzero
FROM mboard_date_map dm
LEFT JOIN mboard_unpivot u
  ON u.col_idx = dm.col_idx AND u.cell IS NOT NULL AND TRIM(u.cell) NOT IN ('', '0')
GROUP BY dm.col_idx, dm.crawl_date
ORDER BY dm.col_idx;

-- 4) 한 셀에 여러 옵션이 '|'로 들어있는 경우 옵션 단위로 분리
DROP TABLE IF EXISTS mboard_tokens;
CREATE TABLE mboard_tokens (
    product_id BIGINT UNSIGNED,
    col_idx INT,
    token VARCHAR(500)
);
INSERT INTO mboard_tokens (product_id, col_idx, token)
WITH RECURSIVE seq AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM seq WHERE n < 10
)
SELECT u.product_id, u.col_idx,
       TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(u.cell, '|', seq.n), '|', -1)) AS token
FROM mboard_unpivot u
JOIN seq
  ON seq.n <= 1 + (LENGTH(u.cell) - LENGTH(REPLACE(u.cell, '|', '')))
WHERE u.cell IS NOT NULL
  AND TRIM(u.cell) NOT IN ('', '0');

-- 5) 옵션명 / 가격 분리 + 벌크·중고(등) 옵션 자체를 가격 데이터에서 제외
--    (숫자가 아닌 값 = '가격비교예정' 등 가격비교 불가 항목은 정규식 조건에서 자동 제외됨)
DROP TABLE IF EXISTS mboard_prices_all;
CREATE TABLE mboard_prices_all (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT UNSIGNED,
    crawl_date DATETIME,
    option_name VARCHAR(300),
    price INT UNSIGNED,
    KEY idx_product_date (product_id, crawl_date)
);
INSERT INTO mboard_prices_all (product_id, crawl_date, option_name, price)
SELECT
    t.product_id,
    m.crawl_date,
    CASE WHEN LOCATE('_', t.token) > 0
         THEN TRIM(BOTH '_' FROM SUBSTRING(t.token, 1, CHAR_LENGTH(t.token) - CHAR_LENGTH(SUBSTRING_INDEX(t.token, '_', -1)) - 1))
         ELSE ''
    END AS option_name,
    CAST(REPLACE(SUBSTRING_INDEX(t.token, '_', -1), ',', '') AS UNSIGNED) AS price
FROM mboard_tokens t
JOIN mboard_date_map m ON m.col_idx = t.col_idx
WHERE t.token <> '0'
  AND SUBSTRING_INDEX(t.token, '_', -1) REGEXP '^[0-9,]+$';

DELETE FROM mboard_prices_all
WHERE option_name LIKE '%중고%' OR option_name LIKE '%리퍼%' OR option_name LIKE '%전시%';

-- 6) 최종 적재 대상 상품 판별
--    - 상품명에 벌크/중고/노트북/리퍼/전시상품 포함 -> 제외
--    - 벌크·중고(RAM은 4개 초과 묶음도 포함) 옵션을 뺀 뒤에도 "실제 유효 가격이 존재하는
--      가장 최근 크롤링일자"에 유효 가격이 하나도 없으면 가격비교불가/단종 상품으로 보고 제외
--    * 기준일은 date_map의 마지막 컬럼이 아니라 mboard_prices_all에서 직접 구함.
--      -> 크롤러가 특정 일자에 실패해서 그 날짜 컬럼이 전부 0/빈값으로 깨져 있어도
--         실제로 데이터가 있는 가장 최근 날짜를 자동으로 기준으로 잡음.
DROP TABLE IF EXISTS mboard_products;
CREATE TABLE mboard_products (
    product_id BIGINT UNSIGNED PRIMARY KEY,
    name       VARCHAR(500),
    company    VARCHAR(50),
    usage_type VARCHAR(20),
    ram_slot_count TINYINT UNSIGNED NULL
);
INSERT INTO mboard_products (product_id, name, company, usage_type, ram_slot_count)
SELECT
    s.id,
    s.name,
    CASE
            WHEN s.name LIKE '%MSI%' THEN 'MSI'
            WHEN s.name LIKE '%ASUS%' THEN 'ASUS'
            WHEN s.name LIKE '%에이수스%' THEN '에이수스'
            ELSE NULL
        END AS company,
    
        CASE WHEN name LIKE '%C621%' OR name LIKE '%C622%' OR name LIKE '%SP3%' OR name LIKE '%SP5%'
                  OR name LIKE '%서버용%' THEN 'server' ELSE 'consumer' END AS usage_type,
    NULL AS ram_slot_count
FROM stg_mboard s
WHERE name NOT LIKE '%중고%'
  AND name NOT LIKE '%노트북%'
  AND name NOT LIKE '%리퍼%'
  AND name NOT LIKE '%전시상품%'
  AND (s.name LIKE '%MSI%' OR s.name LIKE '%ASUS%' OR s.name LIKE '%에이수스%')
  AND EXISTS (
        SELECT 1 FROM mboard_prices_all pp
        WHERE pp.product_id = s.id
          AND pp.crawl_date = (SELECT MAX(crawl_date) FROM mboard_prices_all)
  );

SELECT 'MBoard products (필터 적용 후)' AS info, COUNT(*) AS cnt FROM mboard_products;

-- 7) 최종 가격 테이블: 적재 대상 상품의 가격 이력만 남김
DROP TABLE IF EXISTS mboard_prices;
CREATE TABLE mboard_prices (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT UNSIGNED,
    crawl_date DATETIME,
    option_name VARCHAR(300),
    price INT UNSIGNED,
    KEY idx_product_date (product_id, crawl_date)
);
INSERT INTO mboard_prices (product_id, crawl_date, option_name, price)
SELECT pp.product_id, pp.crawl_date, pp.option_name, pp.price
FROM mboard_prices_all pp
WHERE pp.product_id IN (SELECT product_id FROM mboard_products);

SELECT 'MBoard prices (필터 적용 후)' AS info, COUNT(*) AS cnt FROM mboard_prices;

-- 8) 중간 작업 테이블 정리
DROP TABLE IF EXISTS stg_mboard;
DROP TABLE IF EXISTS mboard_unpivot;
DROP TABLE IF EXISTS mboard_tokens;
DROP TABLE IF EXISTS mboard_prices_all;
DROP TABLE IF EXISTS mboard_date_map;


-- ============================================================
-- Cooler  (crawl_data/Cooler.csv, 6개 일자: 2026-08-01 11:51:25 ~ 2026-08-04 10:45:20)
-- ============================================================

-- 1) 원본 CSV 적재 (스테이징)
DROP TABLE IF EXISTS stg_cooler;
CREATE TABLE stg_cooler (
    id     BIGINT UNSIGNED,
    name   VARCHAR(500),
    d1 TEXT, d2 TEXT, d3 TEXT, d4 TEXT, d5 TEXT, d6 TEXT
);

LOAD DATA LOCAL INFILE 'Danawa-Crawler-fix/crawl_data/Cooler.csv'
INTO TABLE stg_cooler
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SELECT 'Cooler raw rows' AS info, COUNT(*) AS cnt FROM stg_cooler;

-- 2) 날짜 컬럼(dN) <-> 실제 크롤링 일시 매핑
DROP TABLE IF EXISTS cooler_date_map;
CREATE TABLE cooler_date_map (
    col_idx INT PRIMARY KEY,
    crawl_date DATETIME
);
INSERT INTO cooler_date_map (col_idx, crawl_date) VALUES
(1, '2026-08-01 11:51:25'),
(2, '2026-08-02 11:50:37'),
(3, '2026-08-03 09:10:44'),
(4, '2026-08-03 10:28:22'),
(5, '2026-08-03 11:51:52'),
(6, '2026-08-04 10:45:20');

-- 3) 세로로 펼치기 (unpivot) : 전체 원본 상품 기준 (제외 여부는 이후 단계에서 판단)
DROP TABLE IF EXISTS cooler_unpivot;
CREATE TABLE cooler_unpivot (
    product_id BIGINT UNSIGNED,
    col_idx INT,
    cell TEXT
);
INSERT INTO cooler_unpivot (product_id, col_idx, cell)
SELECT id, 1, d1 FROM stg_cooler
UNION ALL SELECT id, 2, d2 FROM stg_cooler
UNION ALL SELECT id, 3, d3 FROM stg_cooler
UNION ALL SELECT id, 4, d4 FROM stg_cooler
UNION ALL SELECT id, 5, d5 FROM stg_cooler
UNION ALL SELECT id, 6, d6 FROM stg_cooler;

-- (참고) 일자별로 값이 있는 상품 수. cnt_nonzero가 0이면 그 날짜는 크롤링이
-- 실패해서 통째로 비어있다는 뜻 (실제로 이런 날짜가 있었음: 예- 특정 날짜 전체 결측).
SELECT 'Cooler 일자별 유효값 개수 (0이면 그 날짜 크롤링 실패)' AS info,
       dm.col_idx, dm.crawl_date,
       COUNT(u.cell) AS cnt_nonzero
FROM cooler_date_map dm
LEFT JOIN cooler_unpivot u
  ON u.col_idx = dm.col_idx AND u.cell IS NOT NULL AND TRIM(u.cell) NOT IN ('', '0')
GROUP BY dm.col_idx, dm.crawl_date
ORDER BY dm.col_idx;

-- 4) 한 셀에 여러 옵션이 '|'로 들어있는 경우 옵션 단위로 분리
DROP TABLE IF EXISTS cooler_tokens;
CREATE TABLE cooler_tokens (
    product_id BIGINT UNSIGNED,
    col_idx INT,
    token VARCHAR(500)
);
INSERT INTO cooler_tokens (product_id, col_idx, token)
WITH RECURSIVE seq AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM seq WHERE n < 10
)
SELECT u.product_id, u.col_idx,
       TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(u.cell, '|', seq.n), '|', -1)) AS token
FROM cooler_unpivot u
JOIN seq
  ON seq.n <= 1 + (LENGTH(u.cell) - LENGTH(REPLACE(u.cell, '|', '')))
WHERE u.cell IS NOT NULL
  AND TRIM(u.cell) NOT IN ('', '0');

-- 5) 옵션명 / 가격 분리 + 벌크·중고(등) 옵션 자체를 가격 데이터에서 제외
--    (숫자가 아닌 값 = '가격비교예정' 등 가격비교 불가 항목은 정규식 조건에서 자동 제외됨)
DROP TABLE IF EXISTS cooler_prices_all;
CREATE TABLE cooler_prices_all (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT UNSIGNED,
    crawl_date DATETIME,
    option_name VARCHAR(300),
    price INT UNSIGNED,
    KEY idx_product_date (product_id, crawl_date)
);
INSERT INTO cooler_prices_all (product_id, crawl_date, option_name, price)
SELECT
    t.product_id,
    m.crawl_date,
    CASE WHEN LOCATE('_', t.token) > 0
         THEN TRIM(BOTH '_' FROM SUBSTRING(t.token, 1, CHAR_LENGTH(t.token) - CHAR_LENGTH(SUBSTRING_INDEX(t.token, '_', -1)) - 1))
         ELSE ''
    END AS option_name,
    CAST(REPLACE(SUBSTRING_INDEX(t.token, '_', -1), ',', '') AS UNSIGNED) AS price
FROM cooler_tokens t
JOIN cooler_date_map m ON m.col_idx = t.col_idx
WHERE t.token <> '0'
  AND SUBSTRING_INDEX(t.token, '_', -1) REGEXP '^[0-9,]+$';

DELETE FROM cooler_prices_all
WHERE option_name LIKE '%중고%' OR option_name LIKE '%리퍼%' OR option_name LIKE '%전시%';

-- 6) 최종 적재 대상 상품 판별
--    - 상품명에 벌크/중고/노트북/리퍼/전시상품 포함 -> 제외
--    - 벌크·중고(RAM은 4개 초과 묶음도 포함) 옵션을 뺀 뒤에도 "실제 유효 가격이 존재하는
--      가장 최근 크롤링일자"에 유효 가격이 하나도 없으면 가격비교불가/단종 상품으로 보고 제외
--    * 기준일은 date_map의 마지막 컬럼이 아니라 cooler_prices_all에서 직접 구함.
--      -> 크롤러가 특정 일자에 실패해서 그 날짜 컬럼이 전부 0/빈값으로 깨져 있어도
--         실제로 데이터가 있는 가장 최근 날짜를 자동으로 기준으로 잡음.
DROP TABLE IF EXISTS cooler_products;
CREATE TABLE cooler_products (
    product_id BIGINT UNSIGNED PRIMARY KEY,
    name       VARCHAR(500),
    company    VARCHAR(50),
    usage_type VARCHAR(20)
);
INSERT INTO cooler_products (product_id, name, company, usage_type)
SELECT
    s.id,
    s.name,
    CASE
            WHEN s.name LIKE '%DEEPCOOL%' THEN 'DEEPCOOL'
            WHEN s.name LIKE '%딥쿨%' THEN '딥쿨'
            ELSE NULL
        END AS company,
    'consumer' AS usage_type
FROM stg_cooler s
WHERE name NOT LIKE '%중고%'
  AND name NOT LIKE '%노트북%'
  AND name NOT LIKE '%리퍼%'
  AND name NOT LIKE '%전시상품%'
  AND (s.name LIKE '%DEEPCOOL%' OR s.name LIKE '%딥쿨%')
  AND EXISTS (
        SELECT 1 FROM cooler_prices_all pp
        WHERE pp.product_id = s.id
          AND pp.crawl_date = (SELECT MAX(crawl_date) FROM cooler_prices_all)
  );

SELECT 'Cooler products (필터 적용 후)' AS info, COUNT(*) AS cnt FROM cooler_products;

-- 7) 최종 가격 테이블: 적재 대상 상품의 가격 이력만 남김
DROP TABLE IF EXISTS cooler_prices;
CREATE TABLE cooler_prices (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT UNSIGNED,
    crawl_date DATETIME,
    option_name VARCHAR(300),
    price INT UNSIGNED,
    KEY idx_product_date (product_id, crawl_date)
);
INSERT INTO cooler_prices (product_id, crawl_date, option_name, price)
SELECT pp.product_id, pp.crawl_date, pp.option_name, pp.price
FROM cooler_prices_all pp
WHERE pp.product_id IN (SELECT product_id FROM cooler_products);

SELECT 'Cooler prices (필터 적용 후)' AS info, COUNT(*) AS cnt FROM cooler_prices;

-- 8) 중간 작업 테이블 정리
DROP TABLE IF EXISTS stg_cooler;
DROP TABLE IF EXISTS cooler_unpivot;
DROP TABLE IF EXISTS cooler_tokens;
DROP TABLE IF EXISTS cooler_prices_all;
DROP TABLE IF EXISTS cooler_date_map;


-- ============================================================
-- Power  (crawl_data/Power.csv, 6개 일자: 2026-08-01 11:51:02 ~ 2026-08-04 10:41:29)
-- ============================================================

-- 1) 원본 CSV 적재 (스테이징)
DROP TABLE IF EXISTS stg_power;
CREATE TABLE stg_power (
    id     BIGINT UNSIGNED,
    name   VARCHAR(500),
    d1 TEXT, d2 TEXT, d3 TEXT, d4 TEXT, d5 TEXT, d6 TEXT
);

LOAD DATA LOCAL INFILE 'Danawa-Crawler-fix/crawl_data/Power.csv'
INTO TABLE stg_power
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SELECT 'Power raw rows' AS info, COUNT(*) AS cnt FROM stg_power;

-- 2) 날짜 컬럼(dN) <-> 실제 크롤링 일시 매핑
DROP TABLE IF EXISTS power_date_map;
CREATE TABLE power_date_map (
    col_idx INT PRIMARY KEY,
    crawl_date DATETIME
);
INSERT INTO power_date_map (col_idx, crawl_date) VALUES
(1, '2026-08-01 11:51:02'),
(2, '2026-08-02 11:50:15'),
(3, '2026-08-03 09:10:18'),
(4, '2026-08-03 10:27:59'),
(5, '2026-08-03 11:51:30'),
(6, '2026-08-04 10:41:29');

-- 3) 세로로 펼치기 (unpivot) : 전체 원본 상품 기준 (제외 여부는 이후 단계에서 판단)
DROP TABLE IF EXISTS power_unpivot;
CREATE TABLE power_unpivot (
    product_id BIGINT UNSIGNED,
    col_idx INT,
    cell TEXT
);
INSERT INTO power_unpivot (product_id, col_idx, cell)
SELECT id, 1, d1 FROM stg_power
UNION ALL SELECT id, 2, d2 FROM stg_power
UNION ALL SELECT id, 3, d3 FROM stg_power
UNION ALL SELECT id, 4, d4 FROM stg_power
UNION ALL SELECT id, 5, d5 FROM stg_power
UNION ALL SELECT id, 6, d6 FROM stg_power;

-- (참고) 일자별로 값이 있는 상품 수. cnt_nonzero가 0이면 그 날짜는 크롤링이
-- 실패해서 통째로 비어있다는 뜻 (실제로 이런 날짜가 있었음: 예- 특정 날짜 전체 결측).
SELECT 'Power 일자별 유효값 개수 (0이면 그 날짜 크롤링 실패)' AS info,
       dm.col_idx, dm.crawl_date,
       COUNT(u.cell) AS cnt_nonzero
FROM power_date_map dm
LEFT JOIN power_unpivot u
  ON u.col_idx = dm.col_idx AND u.cell IS NOT NULL AND TRIM(u.cell) NOT IN ('', '0')
GROUP BY dm.col_idx, dm.crawl_date
ORDER BY dm.col_idx;

-- 4) 한 셀에 여러 옵션이 '|'로 들어있는 경우 옵션 단위로 분리
DROP TABLE IF EXISTS power_tokens;
CREATE TABLE power_tokens (
    product_id BIGINT UNSIGNED,
    col_idx INT,
    token VARCHAR(500)
);
INSERT INTO power_tokens (product_id, col_idx, token)
WITH RECURSIVE seq AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM seq WHERE n < 10
)
SELECT u.product_id, u.col_idx,
       TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(u.cell, '|', seq.n), '|', -1)) AS token
FROM power_unpivot u
JOIN seq
  ON seq.n <= 1 + (LENGTH(u.cell) - LENGTH(REPLACE(u.cell, '|', '')))
WHERE u.cell IS NOT NULL
  AND TRIM(u.cell) NOT IN ('', '0');

-- 5) 옵션명 / 가격 분리 + 벌크·중고(등) 옵션 자체를 가격 데이터에서 제외
--    (숫자가 아닌 값 = '가격비교예정' 등 가격비교 불가 항목은 정규식 조건에서 자동 제외됨)
DROP TABLE IF EXISTS power_prices_all;
CREATE TABLE power_prices_all (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT UNSIGNED,
    crawl_date DATETIME,
    option_name VARCHAR(300),
    price INT UNSIGNED,
    KEY idx_product_date (product_id, crawl_date)
);
INSERT INTO power_prices_all (product_id, crawl_date, option_name, price)
SELECT
    t.product_id,
    m.crawl_date,
    CASE WHEN LOCATE('_', t.token) > 0
         THEN TRIM(BOTH '_' FROM SUBSTRING(t.token, 1, CHAR_LENGTH(t.token) - CHAR_LENGTH(SUBSTRING_INDEX(t.token, '_', -1)) - 1))
         ELSE ''
    END AS option_name,
    CAST(REPLACE(SUBSTRING_INDEX(t.token, '_', -1), ',', '') AS UNSIGNED) AS price
FROM power_tokens t
JOIN power_date_map m ON m.col_idx = t.col_idx
WHERE t.token <> '0'
  AND SUBSTRING_INDEX(t.token, '_', -1) REGEXP '^[0-9,]+$';

DELETE FROM power_prices_all
WHERE option_name LIKE '%중고%' OR option_name LIKE '%리퍼%' OR option_name LIKE '%전시%';

-- 6) 최종 적재 대상 상품 판별
--    - 상품명에 벌크/중고/노트북/리퍼/전시상품 포함 -> 제외
--    - 벌크·중고(RAM은 4개 초과 묶음도 포함) 옵션을 뺀 뒤에도 "실제 유효 가격이 존재하는
--      가장 최근 크롤링일자"에 유효 가격이 하나도 없으면 가격비교불가/단종 상품으로 보고 제외
--    * 기준일은 date_map의 마지막 컬럼이 아니라 power_prices_all에서 직접 구함.
--      -> 크롤러가 특정 일자에 실패해서 그 날짜 컬럼이 전부 0/빈값으로 깨져 있어도
--         실제로 데이터가 있는 가장 최근 날짜를 자동으로 기준으로 잡음.
DROP TABLE IF EXISTS power_products;
CREATE TABLE power_products (
    product_id BIGINT UNSIGNED PRIMARY KEY,
    name       VARCHAR(500),
    company    VARCHAR(50),
    usage_type VARCHAR(20)
);
INSERT INTO power_products (product_id, name, company, usage_type)
SELECT
    s.id,
    s.name,
    CASE
            WHEN s.name LIKE '%마이크로닉스%' THEN '마이크로닉스'
            ELSE NULL
        END AS company,
    
        CASE WHEN name LIKE '%서버용%' OR name LIKE '%redundant%' THEN 'server' ELSE 'consumer' END AS usage_type
FROM stg_power s
WHERE name NOT LIKE '%중고%'
  AND name NOT LIKE '%노트북%'
  AND name NOT LIKE '%리퍼%'
  AND name NOT LIKE '%전시상품%'
  AND (s.name LIKE '%마이크로닉스%')
  AND EXISTS (
        SELECT 1 FROM power_prices_all pp
        WHERE pp.product_id = s.id
          AND pp.crawl_date = (SELECT MAX(crawl_date) FROM power_prices_all)
  );

SELECT 'Power products (필터 적용 후)' AS info, COUNT(*) AS cnt FROM power_products;

-- 7) 최종 가격 테이블: 적재 대상 상품의 가격 이력만 남김
DROP TABLE IF EXISTS power_prices;
CREATE TABLE power_prices (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT UNSIGNED,
    crawl_date DATETIME,
    option_name VARCHAR(300),
    price INT UNSIGNED,
    KEY idx_product_date (product_id, crawl_date)
);
INSERT INTO power_prices (product_id, crawl_date, option_name, price)
SELECT pp.product_id, pp.crawl_date, pp.option_name, pp.price
FROM power_prices_all pp
WHERE pp.product_id IN (SELECT product_id FROM power_products);

SELECT 'Power prices (필터 적용 후)' AS info, COUNT(*) AS cnt FROM power_prices;

-- 8) 중간 작업 테이블 정리
DROP TABLE IF EXISTS stg_power;
DROP TABLE IF EXISTS power_unpivot;
DROP TABLE IF EXISTS power_tokens;
DROP TABLE IF EXISTS power_prices_all;
DROP TABLE IF EXISTS power_date_map;


-- ============================================================
-- Case  (crawl_data/Case.csv, 6개 일자: 2026-08-01 11:51:43 ~ 2026-08-04 10:53:08)
-- ============================================================

-- 1) 원본 CSV 적재 (스테이징)
DROP TABLE IF EXISTS stg_case;
CREATE TABLE stg_case (
    id     BIGINT UNSIGNED,
    name   VARCHAR(500),
    d1 TEXT, d2 TEXT, d3 TEXT, d4 TEXT, d5 TEXT, d6 TEXT
);

LOAD DATA LOCAL INFILE 'Danawa-Crawler-fix/crawl_data/Case.csv'
INTO TABLE stg_case
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SELECT 'Case raw rows' AS info, COUNT(*) AS cnt FROM stg_case;

-- 2) 날짜 컬럼(dN) <-> 실제 크롤링 일시 매핑
DROP TABLE IF EXISTS case_date_map;
CREATE TABLE case_date_map (
    col_idx INT PRIMARY KEY,
    crawl_date DATETIME
);
INSERT INTO case_date_map (col_idx, crawl_date) VALUES
(1, '2026-08-01 11:51:43'),
(2, '2026-08-02 11:50:59'),
(3, '2026-08-03 09:11:02'),
(4, '2026-08-03 10:28:43'),
(5, '2026-08-03 11:52:13'),
(6, '2026-08-04 10:53:08');

-- 3) 세로로 펼치기 (unpivot) : 전체 원본 상품 기준 (제외 여부는 이후 단계에서 판단)
DROP TABLE IF EXISTS case_unpivot;
CREATE TABLE case_unpivot (
    product_id BIGINT UNSIGNED,
    col_idx INT,
    cell TEXT
);
INSERT INTO case_unpivot (product_id, col_idx, cell)
SELECT id, 1, d1 FROM stg_case
UNION ALL SELECT id, 2, d2 FROM stg_case
UNION ALL SELECT id, 3, d3 FROM stg_case
UNION ALL SELECT id, 4, d4 FROM stg_case
UNION ALL SELECT id, 5, d5 FROM stg_case
UNION ALL SELECT id, 6, d6 FROM stg_case;

-- (참고) 일자별로 값이 있는 상품 수. cnt_nonzero가 0이면 그 날짜는 크롤링이
-- 실패해서 통째로 비어있다는 뜻 (실제로 이런 날짜가 있었음: 예- 특정 날짜 전체 결측).
SELECT 'Case 일자별 유효값 개수 (0이면 그 날짜 크롤링 실패)' AS info,
       dm.col_idx, dm.crawl_date,
       COUNT(u.cell) AS cnt_nonzero
FROM case_date_map dm
LEFT JOIN case_unpivot u
  ON u.col_idx = dm.col_idx AND u.cell IS NOT NULL AND TRIM(u.cell) NOT IN ('', '0')
GROUP BY dm.col_idx, dm.crawl_date
ORDER BY dm.col_idx;

-- 4) 한 셀에 여러 옵션이 '|'로 들어있는 경우 옵션 단위로 분리
DROP TABLE IF EXISTS case_tokens;
CREATE TABLE case_tokens (
    product_id BIGINT UNSIGNED,
    col_idx INT,
    token VARCHAR(500)
);
INSERT INTO case_tokens (product_id, col_idx, token)
WITH RECURSIVE seq AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM seq WHERE n < 10
)
SELECT u.product_id, u.col_idx,
       TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(u.cell, '|', seq.n), '|', -1)) AS token
FROM case_unpivot u
JOIN seq
  ON seq.n <= 1 + (LENGTH(u.cell) - LENGTH(REPLACE(u.cell, '|', '')))
WHERE u.cell IS NOT NULL
  AND TRIM(u.cell) NOT IN ('', '0');

-- 5) 옵션명 / 가격 분리 + 벌크·중고(등) 옵션 자체를 가격 데이터에서 제외
--    (숫자가 아닌 값 = '가격비교예정' 등 가격비교 불가 항목은 정규식 조건에서 자동 제외됨)
DROP TABLE IF EXISTS case_prices_all;
CREATE TABLE case_prices_all (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT UNSIGNED,
    crawl_date DATETIME,
    option_name VARCHAR(300),
    price INT UNSIGNED,
    KEY idx_product_date (product_id, crawl_date)
);
INSERT INTO case_prices_all (product_id, crawl_date, option_name, price)
SELECT
    t.product_id,
    m.crawl_date,
    CASE WHEN LOCATE('_', t.token) > 0
         THEN TRIM(BOTH '_' FROM SUBSTRING(t.token, 1, CHAR_LENGTH(t.token) - CHAR_LENGTH(SUBSTRING_INDEX(t.token, '_', -1)) - 1))
         ELSE ''
    END AS option_name,
    CAST(REPLACE(SUBSTRING_INDEX(t.token, '_', -1), ',', '') AS UNSIGNED) AS price
FROM case_tokens t
JOIN case_date_map m ON m.col_idx = t.col_idx
WHERE t.token <> '0'
  AND SUBSTRING_INDEX(t.token, '_', -1) REGEXP '^[0-9,]+$';

DELETE FROM case_prices_all
WHERE option_name LIKE '%중고%' OR option_name LIKE '%리퍼%' OR option_name LIKE '%전시%';

-- 6) 최종 적재 대상 상품 판별
--    - 상품명에 벌크/중고/노트북/리퍼/전시상품 포함 -> 제외
--    - 벌크·중고(RAM은 4개 초과 묶음도 포함) 옵션을 뺀 뒤에도 "실제 유효 가격이 존재하는
--      가장 최근 크롤링일자"에 유효 가격이 하나도 없으면 가격비교불가/단종 상품으로 보고 제외
--    * 기준일은 date_map의 마지막 컬럼이 아니라 case_prices_all에서 직접 구함.
--      -> 크롤러가 특정 일자에 실패해서 그 날짜 컬럼이 전부 0/빈값으로 깨져 있어도
--         실제로 데이터가 있는 가장 최근 날짜를 자동으로 기준으로 잡음.
DROP TABLE IF EXISTS case_products;
CREATE TABLE case_products (
    product_id BIGINT UNSIGNED PRIMARY KEY,
    name       VARCHAR(500),
    company    VARCHAR(50),
    usage_type VARCHAR(20)
);
INSERT INTO case_products (product_id, name, company, usage_type)
SELECT
    s.id,
    s.name,
    CASE
            WHEN s.name LIKE '%darkFlash%' THEN 'darkFlash'
            WHEN s.name LIKE '%다크플래시%' THEN '다크플래시'
            WHEN s.name LIKE '%앱코%' THEN '앱코'
            WHEN s.name LIKE '%ABKO%' THEN 'ABKO'
            ELSE NULL
        END AS company,
    
        CASE WHEN name LIKE '%랙마운트%' OR name LIKE '%서버케이스%' OR name LIKE '%rack%' THEN 'server' ELSE 'consumer' END AS usage_type
FROM stg_case s
WHERE name NOT LIKE '%중고%'
  AND name NOT LIKE '%노트북%'
  AND name NOT LIKE '%리퍼%'
  AND name NOT LIKE '%전시상품%'
  AND (s.name LIKE '%darkFlash%' OR s.name LIKE '%다크플래시%' OR s.name LIKE '%앱코%' OR s.name LIKE '%ABKO%')
  AND EXISTS (
        SELECT 1 FROM case_prices_all pp
        WHERE pp.product_id = s.id
          AND pp.crawl_date = (SELECT MAX(crawl_date) FROM case_prices_all)
  );

SELECT 'Case products (필터 적용 후)' AS info, COUNT(*) AS cnt FROM case_products;

-- 7) 최종 가격 테이블: 적재 대상 상품의 가격 이력만 남김
DROP TABLE IF EXISTS case_prices;
CREATE TABLE case_prices (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT UNSIGNED,
    crawl_date DATETIME,
    option_name VARCHAR(300),
    price INT UNSIGNED,
    KEY idx_product_date (product_id, crawl_date)
);
INSERT INTO case_prices (product_id, crawl_date, option_name, price)
SELECT pp.product_id, pp.crawl_date, pp.option_name, pp.price
FROM case_prices_all pp
WHERE pp.product_id IN (SELECT product_id FROM case_products);

SELECT 'Case prices (필터 적용 후)' AS info, COUNT(*) AS cnt FROM case_prices;

-- 8) 중간 작업 테이블 정리
DROP TABLE IF EXISTS stg_case;
DROP TABLE IF EXISTS case_unpivot;
DROP TABLE IF EXISTS case_tokens;
DROP TABLE IF EXISTS case_prices_all;
DROP TABLE IF EXISTS case_date_map;


-- ============================================================
-- Monitor  (crawl_data/Monitor.csv, 6개 일자: 2026-08-01 11:51:06 ~ 2026-08-04 10:42:41)
-- ============================================================

-- 1) 원본 CSV 적재 (스테이징)
DROP TABLE IF EXISTS stg_monitor;
CREATE TABLE stg_monitor (
    id     BIGINT UNSIGNED,
    name   VARCHAR(500),
    d1 TEXT, d2 TEXT, d3 TEXT, d4 TEXT, d5 TEXT, d6 TEXT
);

LOAD DATA LOCAL INFILE 'Danawa-Crawler-fix/crawl_data/Monitor.csv'
INTO TABLE stg_monitor
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SELECT 'Monitor raw rows' AS info, COUNT(*) AS cnt FROM stg_monitor;

-- 2) 날짜 컬럼(dN) <-> 실제 크롤링 일시 매핑
DROP TABLE IF EXISTS monitor_date_map;
CREATE TABLE monitor_date_map (
    col_idx INT PRIMARY KEY,
    crawl_date DATETIME
);
INSERT INTO monitor_date_map (col_idx, crawl_date) VALUES
(1, '2026-08-01 11:51:06'),
(2, '2026-08-02 11:50:18'),
(3, '2026-08-03 09:10:28'),
(4, '2026-08-03 10:28:03'),
(5, '2026-08-03 11:51:34'),
(6, '2026-08-04 10:42:41');

-- 3) 세로로 펼치기 (unpivot) : 전체 원본 상품 기준 (제외 여부는 이후 단계에서 판단)
DROP TABLE IF EXISTS monitor_unpivot;
CREATE TABLE monitor_unpivot (
    product_id BIGINT UNSIGNED,
    col_idx INT,
    cell TEXT
);
INSERT INTO monitor_unpivot (product_id, col_idx, cell)
SELECT id, 1, d1 FROM stg_monitor
UNION ALL SELECT id, 2, d2 FROM stg_monitor
UNION ALL SELECT id, 3, d3 FROM stg_monitor
UNION ALL SELECT id, 4, d4 FROM stg_monitor
UNION ALL SELECT id, 5, d5 FROM stg_monitor
UNION ALL SELECT id, 6, d6 FROM stg_monitor;

-- (참고) 일자별로 값이 있는 상품 수. cnt_nonzero가 0이면 그 날짜는 크롤링이
-- 실패해서 통째로 비어있다는 뜻 (실제로 이런 날짜가 있었음: 예- 특정 날짜 전체 결측).
SELECT 'Monitor 일자별 유효값 개수 (0이면 그 날짜 크롤링 실패)' AS info,
       dm.col_idx, dm.crawl_date,
       COUNT(u.cell) AS cnt_nonzero
FROM monitor_date_map dm
LEFT JOIN monitor_unpivot u
  ON u.col_idx = dm.col_idx AND u.cell IS NOT NULL AND TRIM(u.cell) NOT IN ('', '0')
GROUP BY dm.col_idx, dm.crawl_date
ORDER BY dm.col_idx;

-- 4) 한 셀에 여러 옵션이 '|'로 들어있는 경우 옵션 단위로 분리
DROP TABLE IF EXISTS monitor_tokens;
CREATE TABLE monitor_tokens (
    product_id BIGINT UNSIGNED,
    col_idx INT,
    token VARCHAR(500)
);
INSERT INTO monitor_tokens (product_id, col_idx, token)
WITH RECURSIVE seq AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM seq WHERE n < 10
)
SELECT u.product_id, u.col_idx,
       TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(u.cell, '|', seq.n), '|', -1)) AS token
FROM monitor_unpivot u
JOIN seq
  ON seq.n <= 1 + (LENGTH(u.cell) - LENGTH(REPLACE(u.cell, '|', '')))
WHERE u.cell IS NOT NULL
  AND TRIM(u.cell) NOT IN ('', '0');

-- 5) 옵션명 / 가격 분리 + 벌크·중고(등) 옵션 자체를 가격 데이터에서 제외
--    (숫자가 아닌 값 = '가격비교예정' 등 가격비교 불가 항목은 정규식 조건에서 자동 제외됨)
DROP TABLE IF EXISTS monitor_prices_all;
CREATE TABLE monitor_prices_all (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT UNSIGNED,
    crawl_date DATETIME,
    option_name VARCHAR(300),
    price INT UNSIGNED,
    KEY idx_product_date (product_id, crawl_date)
);
INSERT INTO monitor_prices_all (product_id, crawl_date, option_name, price)
SELECT
    t.product_id,
    m.crawl_date,
    CASE WHEN LOCATE('_', t.token) > 0
         THEN TRIM(BOTH '_' FROM SUBSTRING(t.token, 1, CHAR_LENGTH(t.token) - CHAR_LENGTH(SUBSTRING_INDEX(t.token, '_', -1)) - 1))
         ELSE ''
    END AS option_name,
    CAST(REPLACE(SUBSTRING_INDEX(t.token, '_', -1), ',', '') AS UNSIGNED) AS price
FROM monitor_tokens t
JOIN monitor_date_map m ON m.col_idx = t.col_idx
WHERE t.token <> '0'
  AND SUBSTRING_INDEX(t.token, '_', -1) REGEXP '^[0-9,]+$';

DELETE FROM monitor_prices_all
WHERE option_name LIKE '%중고%' OR option_name LIKE '%리퍼%' OR option_name LIKE '%전시%';

-- 6) 최종 적재 대상 상품 판별
--    - 상품명에 벌크/중고/노트북/리퍼/전시상품 포함 -> 제외
--    - 벌크·중고(RAM은 4개 초과 묶음도 포함) 옵션을 뺀 뒤에도 "실제 유효 가격이 존재하는
--      가장 최근 크롤링일자"에 유효 가격이 하나도 없으면 가격비교불가/단종 상품으로 보고 제외
--    * 기준일은 date_map의 마지막 컬럼이 아니라 monitor_prices_all에서 직접 구함.
--      -> 크롤러가 특정 일자에 실패해서 그 날짜 컬럼이 전부 0/빈값으로 깨져 있어도
--         실제로 데이터가 있는 가장 최근 날짜를 자동으로 기준으로 잡음.
DROP TABLE IF EXISTS monitor_products;
CREATE TABLE monitor_products (
    product_id BIGINT UNSIGNED PRIMARY KEY,
    name       VARCHAR(500),
    company    VARCHAR(50),
    usage_type VARCHAR(20)
);
INSERT INTO monitor_products (product_id, name, company, usage_type)
SELECT
    s.id,
    s.name,
    SUBSTRING_INDEX(s.name, ' ', 1) AS company,
    'consumer' AS usage_type
FROM stg_monitor s
WHERE name NOT LIKE '%중고%'
  AND name NOT LIKE '%노트북%'
  AND name NOT LIKE '%리퍼%'
  AND name NOT LIKE '%전시상품%'
  AND EXISTS (
        SELECT 1 FROM monitor_prices_all pp
        WHERE pp.product_id = s.id
          AND pp.crawl_date = (SELECT MAX(crawl_date) FROM monitor_prices_all)
  );

SELECT 'Monitor products (필터 적용 후)' AS info, COUNT(*) AS cnt FROM monitor_products;

-- 7) 최종 가격 테이블: 적재 대상 상품의 가격 이력만 남김
DROP TABLE IF EXISTS monitor_prices;
CREATE TABLE monitor_prices (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT UNSIGNED,
    crawl_date DATETIME,
    option_name VARCHAR(300),
    price INT UNSIGNED,
    KEY idx_product_date (product_id, crawl_date)
);
INSERT INTO monitor_prices (product_id, crawl_date, option_name, price)
SELECT pp.product_id, pp.crawl_date, pp.option_name, pp.price
FROM monitor_prices_all pp
WHERE pp.product_id IN (SELECT product_id FROM monitor_products);

SELECT 'Monitor prices (필터 적용 후)' AS info, COUNT(*) AS cnt FROM monitor_prices;

-- 8) 중간 작업 테이블 정리
DROP TABLE IF EXISTS stg_monitor;
DROP TABLE IF EXISTS monitor_unpivot;
DROP TABLE IF EXISTS monitor_tokens;
DROP TABLE IF EXISTS monitor_prices_all;
DROP TABLE IF EXISTS monitor_date_map;

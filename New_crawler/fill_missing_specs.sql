-- ============================================================
-- 누락 스펙 채우기 통합본
-- - HDD 용량 / 쿨러 TDP : 확정 (discovery 결과로 패턴 확인 완료, 바로 실행 가능)
-- - RAM 용량 / SSD 용량 / 케이스 라디에이터 : discovery_missing_specs_v2.sql 결과 받는 대로
--   이 파일의 해당 섹션만 채워서 다시 드립니다 (지금은 자리만 비워둠, 실행해도 에러 안 남)
-- 전제조건: add_missing_spec_columns.sql 로 컬럼 추가가 이미 완료되어 있어야 함
-- ============================================================
USE DW_db;
SET SQL_SAFE_UPDATES = 0;

-- ============================================================
-- 1) HDD 용량 (확정) - spec_key 없이 순수 "1TB", "500GB" 형태
-- ============================================================
UPDATE IGNORE hdd_products p
JOIN (
    SELECT product_id,
           CASE
               WHEN spec_value LIKE '%TB' THEN CAST(REPLACE(spec_value, 'TB', '') AS UNSIGNED) * 1000
               WHEN spec_value LIKE '%GB' THEN CAST(REPLACE(spec_value, 'GB', '') AS UNSIGNED)
           END AS cap
    FROM danawa_spec_summary
    WHERE category = 'hdd'
      AND spec_key IS NULL
      AND spec_value REGEXP '^[0-9]+(GB|TB)$'
) spec ON spec.product_id = p.product_id
SET p.capacity_gb = spec.cap
WHERE p.capacity_gb IS NULL;

SELECT 'hdd capacity_gb 채워진 개수' AS info, COUNT(*) AS cnt FROM hdd_products WHERE capacity_gb IS NOT NULL;
SELECT product_id, name FROM hdd_products WHERE capacity_gb IS NULL LIMIT 20;

-- ============================================================
-- 2) 쿨러 TDP (확정) - spec_key='TDP', 값은 "130W" 또는 "TDP 100W" 두 형태 혼재
-- ============================================================
UPDATE IGNORE cooler_products p
JOIN (
    SELECT product_id,
           MAX(CAST(REGEXP_REPLACE(spec_value, '[^0-9]', '') AS UNSIGNED)) AS w
    FROM danawa_spec_summary
    WHERE category = 'cooler'
      AND spec_key = 'TDP'
      AND spec_value REGEXP '[0-9]+W'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.tdp_rating_w = spec.w
WHERE p.tdp_rating_w IS NULL;

SELECT 'cooler tdp_rating_w 채워진 개수' AS info, COUNT(*) AS cnt FROM cooler_products WHERE tdp_rating_w IS NOT NULL;
SELECT product_id, name FROM cooler_products WHERE tdp_rating_w IS NULL LIMIT 20;

-- ============================================================
-- 3) RAM 용량 - 상품 하나에 용량이 여러 개 옵션으로 걸려있는 구조라
--    products 테이블에 컬럼 추가 대신 별도 옵션 테이블로 분리.
--    option_name이 실제로는 "16GB_12,113원/1GB" 형태(1GB당 단가 표시)라
--    '_' 앞부분만 잘라서 용량으로 사용.
-- ============================================================
ALTER TABLE ram_products DROP COLUMN capacity_gb;  -- 미사용 컬럼 정리 (이미 없으면 에러나도 무시)

DROP TABLE IF EXISTS ram_options;
CREATE TABLE ram_options (
    id          BIGINT AUTO_INCREMENT PRIMARY KEY,
    product_id  BIGINT UNSIGNED NOT NULL,
    capacity_gb SMALLINT UNSIGNED NOT NULL,
    price       INT UNSIGNED,
    crawl_date  DATETIME,
    KEY idx_product (product_id)
);

INSERT INTO ram_options (product_id, capacity_gb, price, crawl_date)
SELECT
    rp.product_id,
    CASE
        WHEN cap_str LIKE '%TB' THEN CAST(REPLACE(cap_str, 'TB', '') AS UNSIGNED) * 1000
        WHEN cap_str LIKE '%GB' THEN CAST(REPLACE(cap_str, 'GB', '') AS UNSIGNED)
    END AS capacity_gb,
    rp.price,
    rp.crawl_date
FROM (
    SELECT product_id, price, crawl_date,
           SUBSTRING_INDEX(option_name, '_', 1) AS cap_str
    FROM ram_prices
    WHERE crawl_date = (SELECT MAX(crawl_date) FROM ram_prices)
) rp
WHERE rp.cap_str REGEXP '^[0-9]+(GB|TB)$'
  AND rp.product_id IN (SELECT product_id FROM ram_products);

SELECT 'ram_options 생성된 행 수' AS info, COUNT(*) AS cnt FROM ram_options;
SELECT capacity_gb, COUNT(*) AS cnt FROM ram_options GROUP BY capacity_gb ORDER BY capacity_gb;

-- ============================================================
-- 4) SSD 용량 - RAM과 동일한 구조/방식
-- ============================================================
ALTER TABLE ssd_products DROP COLUMN capacity_gb;  -- 미사용 컬럼 정리

DROP TABLE IF EXISTS ssd_options;
CREATE TABLE ssd_options (
    id          BIGINT AUTO_INCREMENT PRIMARY KEY,
    product_id  BIGINT UNSIGNED NOT NULL,
    capacity_gb INT UNSIGNED NOT NULL,
    price       INT UNSIGNED,
    crawl_date  DATETIME,
    KEY idx_product (product_id)
);

INSERT INTO ssd_options (product_id, capacity_gb, price, crawl_date)
SELECT
    sp.product_id,
    CASE
        WHEN cap_str LIKE '%TB' THEN CAST(REPLACE(cap_str, 'TB', '') AS UNSIGNED) * 1000
        WHEN cap_str LIKE '%GB' THEN CAST(REPLACE(cap_str, 'GB', '') AS UNSIGNED)
    END AS capacity_gb,
    sp.price,
    sp.crawl_date
FROM (
    SELECT product_id, price, crawl_date,
           SUBSTRING_INDEX(option_name, '_', 1) AS cap_str
    FROM ssd_prices
    WHERE crawl_date = (SELECT MAX(crawl_date) FROM ssd_prices)
) sp
WHERE sp.cap_str REGEXP '^[0-9]+(GB|TB)$'
  AND sp.product_id IN (SELECT product_id FROM ssd_products);

SELECT 'ssd_options 생성된 행 수' AS info, COUNT(*) AS cnt FROM ssd_options;
SELECT capacity_gb, COUNT(*) AS cnt FROM ssd_options GROUP BY capacity_gb ORDER BY capacity_gb;

-- ============================================================
-- 5) 케이스 라디에이터 지원 규격 (확정)
--    상단/전면/후면/내부측면 팬 장착 위치의 "크기 x 개수"를 라디에이터 규격으로 환산
--    예: "상단 120mm LED x3" -> 상단 라디에이터 360mm 지원으로 계산
--        "내부 측면 120mm"(개수 표기 없으면 x1로 간주) -> 120mm
-- ============================================================
ALTER TABLE case_products
    ADD COLUMN radiator_front_mm VARCHAR(50) NULL;

-- 계산 공통 서브쿼리 패턴: 위치별로 spec_value에서 mm값과 x개수를 뽑아 곱함
UPDATE IGNORE case_products p
JOIN (
    SELECT product_id,
           MAX(
               CAST(REGEXP_REPLACE(REGEXP_SUBSTR(spec_value, '[0-9]+mm'), 'mm', '') AS UNSIGNED)
               * COALESCE(CAST(REGEXP_REPLACE(REGEXP_SUBSTR(spec_value, 'x[0-9]+'), 'x', '') AS UNSIGNED), 1)
           ) AS mm
    FROM danawa_spec_summary
    WHERE category = 'case' AND spec_key = '상단' AND spec_value REGEXP '[0-9]+mm'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.radiator_top_mm = spec.mm
WHERE p.radiator_top_mm IS NULL;

UPDATE IGNORE case_products p
JOIN (
    SELECT product_id,
           MAX(
               CAST(REGEXP_REPLACE(REGEXP_SUBSTR(spec_value, '[0-9]+mm'), 'mm', '') AS UNSIGNED)
               * COALESCE(CAST(REGEXP_REPLACE(REGEXP_SUBSTR(spec_value, 'x[0-9]+'), 'x', '') AS UNSIGNED), 1)
           ) AS mm
    FROM danawa_spec_summary
    WHERE category = 'case' AND spec_key = '전면' AND spec_value REGEXP '[0-9]+mm'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.radiator_front_mm = spec.mm
WHERE p.radiator_front_mm IS NULL;

UPDATE IGNORE case_products p
JOIN (
    SELECT product_id,
           MAX(
               CAST(REGEXP_REPLACE(REGEXP_SUBSTR(spec_value, '[0-9]+mm'), 'mm', '') AS UNSIGNED)
               * COALESCE(CAST(REGEXP_REPLACE(REGEXP_SUBSTR(spec_value, 'x[0-9]+'), 'x', '') AS UNSIGNED), 1)
           ) AS mm
    FROM danawa_spec_summary
    WHERE category = 'case' AND spec_key = '후면' AND spec_value REGEXP '[0-9]+mm'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.radiator_rear_mm = spec.mm
WHERE p.radiator_rear_mm IS NULL;

UPDATE IGNORE case_products p
JOIN (
    SELECT product_id,
           MAX(
               CAST(REGEXP_REPLACE(REGEXP_SUBSTR(spec_value, '[0-9]+mm'), 'mm', '') AS UNSIGNED)
               * COALESCE(CAST(REGEXP_REPLACE(REGEXP_SUBSTR(spec_value, 'x[0-9]+'), 'x', '') AS UNSIGNED), 1)
           ) AS mm
    FROM danawa_spec_summary
    WHERE category = 'case' AND spec_key = '내부 측면' AND spec_value REGEXP '[0-9]+mm'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.radiator_side_mm = spec.mm
WHERE p.radiator_side_mm IS NULL;

SELECT 'case radiator_top_mm 채워진 개수' AS info, COUNT(*) AS cnt FROM case_products WHERE radiator_top_mm IS NOT NULL;
SELECT 'case radiator_front_mm 채워진 개수' AS info, COUNT(*) AS cnt FROM case_products WHERE radiator_front_mm IS NOT NULL;
SELECT 'case radiator_rear_mm 채워진 개수' AS info, COUNT(*) AS cnt FROM case_products WHERE radiator_rear_mm IS NOT NULL;
SELECT 'case radiator_side_mm 채워진 개수' AS info, COUNT(*) AS cnt FROM case_products WHERE radiator_side_mm IS NOT NULL;

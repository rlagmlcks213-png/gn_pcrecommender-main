-- ============================================================
-- 쿨러: 라디에이터 길이/두께(수랭용) + 공랭/수랭 구분(cooler_type) 채우기
-- cooler_type 컬럼은 add_compat_columns.sql에서 이미 만들어져 있었지만
-- 지금까지 안 채워져 있었음(값 없는 빈 컬럼) - 이번에 채움.
-- ============================================================
USE DW_db;
SET SQL_SAFE_UPDATES = 0;

ALTER TABLE cooler_products
    ADD COLUMN radiator_length_mm    SMALLINT UNSIGNED NULL,   -- 예: 280, 395, 462
    ADD COLUMN radiator_thickness_mm SMALLINT UNSIGNED NULL;   -- 예: 27

-- ---------- 1) 라디에이터 길이(mm) ----------
UPDATE IGNORE cooler_products p
JOIN (
    SELECT product_id, MAX(CAST(REPLACE(spec_value, 'mm', '') AS UNSIGNED)) AS len
    FROM danawa_spec_summary
    WHERE category = 'cooler'
      AND spec_key = '라디에이터 길이'
      AND spec_value REGEXP '^[0-9]+mm$'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.radiator_length_mm = spec.len
WHERE p.radiator_length_mm IS NULL;

-- ---------- 2) 라디에이터 두께(mm) ----------
UPDATE IGNORE cooler_products p
JOIN (
    SELECT product_id, MAX(CAST(REPLACE(spec_value, 'mm', '') AS UNSIGNED)) AS th
    FROM danawa_spec_summary
    WHERE category = 'cooler'
      AND spec_key = '라디에이터 두께'
      AND spec_value REGEXP '^[0-9]+mm$'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.radiator_thickness_mm = spec.th
WHERE p.radiator_thickness_mm IS NULL;

-- ---------- 3) 공랭/수랭 구분 ----------
-- 라디에이터 길이가 있으면 무조건 수랭. 그 외엔 spec 텍스트의 '공랭'/'수랭'/'[수랭]' 표기로 판단.
UPDATE IGNORE cooler_products p
SET p.cooler_type = '수랭'
WHERE p.radiator_length_mm IS NOT NULL
  AND p.cooler_type IS NULL;

UPDATE IGNORE cooler_products p
JOIN (
    SELECT DISTINCT product_id
    FROM danawa_spec_summary
    WHERE category = 'cooler'
      AND (spec_value LIKE '%수랭%')
) spec ON spec.product_id = p.product_id
SET p.cooler_type = '수랭'
WHERE p.cooler_type IS NULL;

UPDATE IGNORE cooler_products p
JOIN (
    SELECT DISTINCT product_id
    FROM danawa_spec_summary
    WHERE category = 'cooler'
      AND spec_value LIKE '%공랭%'
) spec ON spec.product_id = p.product_id
SET p.cooler_type = '공랭'
WHERE p.cooler_type IS NULL;

-- 그래도 안 채워진 나머지는, 높이(height_mm)는 있는데 라디에이터 정보가 전혀 없는 경우이므로 공랭으로 간주
UPDATE cooler_products
SET cooler_type = '공랭'
WHERE cooler_type IS NULL AND height_mm IS NOT NULL;

SELECT 'cooler radiator_length_mm 채워진 개수' AS info, COUNT(*) AS cnt FROM cooler_products WHERE radiator_length_mm IS NOT NULL;
SELECT 'cooler radiator_thickness_mm 채워진 개수' AS info, COUNT(*) AS cnt FROM cooler_products WHERE radiator_thickness_mm IS NOT NULL;
SELECT cooler_type, COUNT(*) AS cnt FROM cooler_products GROUP BY cooler_type;
SELECT product_id, name FROM cooler_products WHERE cooler_type IS NULL;

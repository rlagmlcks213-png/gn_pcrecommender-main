-- ============================================================
-- cooler_products.tdp_rating_w 컬럼이 없는 경우를 위한 안전 보강 스크립트.
-- (MySQL은 ADD COLUMN IF NOT EXISTS를 지원하지 않는다 — MariaDB 전용 문법이다.
-- 이미 컬럼이 있으면 이 ALTER TABLE 문장만 에러가 나고 나머지는 정상 진행된다 —
-- db/load_real_data.py가 문장 단위로 실행해서 한 줄 실패해도 계속 진행한다.)
-- ============================================================
USE DW_db;

ALTER TABLE cooler_products
    ADD COLUMN tdp_rating_w SMALLINT UNSIGNED NULL;

-- danawa_spec_summary에서 실제 TDP 값을 채운다(팀원 fill_missing_specs.sql과 동일 로직)
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

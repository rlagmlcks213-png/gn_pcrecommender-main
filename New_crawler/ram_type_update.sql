-- ============================================================
-- RAM 규격(DDR4/DDR5) 채우기
-- 전제조건: add_compat_columns.sql 실행 완료 + spec_scraper.py --category ram 완료
-- 실제 형태: spec_key는 NULL, spec_value가 정확히 "DDR4" 또는 "DDR5"
-- ============================================================
USE DW_db;
SET SQL_SAFE_UPDATES = 0;
UPDATE IGNORE ram_products p
JOIN (
    SELECT product_id, MIN(spec_value) AS rtype
    FROM danawa_spec_summary
    WHERE category = 'ram' AND spec_value IN ('DDR4', 'DDR5', 'LPDDR4', 'LPDDR5')
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.ram_type = spec.rtype
WHERE p.ram_type IS NULL;

SELECT 'ram ram_type 채워진 개수' AS info, COUNT(*) AS cnt FROM ram_products WHERE ram_type IS NOT NULL;
SELECT ram_type, COUNT(*) cnt FROM ram_products GROUP BY ram_type ORDER BY cnt DESC;

-- ============================================================
-- VGA 길이 / 권장 파워용량 / 전원 커넥터 채우기
-- 전제조건: add_compat_columns.sql 실행 완료 + spec_scraper.py --category vga 완료
-- 실제 형태:
--   길이:      spec_key = "가로(길이)", spec_value = "148mm"
--   권장파워:  spec_key는 보통 NULL, spec_value = "450W 이상", "750W 이상" 등
--   전원커넥터: spec_key = "전원 포트", spec_value = "8핀 x1" 등
-- ============================================================
USE DW_db;
SET SQL_SAFE_UPDATES = 0;
-- 1) 길이 (mm)
UPDATE IGNORE vga_products p
JOIN (
    SELECT product_id, MIN(CAST(REPLACE(spec_value, 'mm', '') AS UNSIGNED)) AS l
    FROM danawa_spec_summary
    WHERE category = 'vga'
      AND spec_key = '가로(길이)'
      AND spec_value REGEXP '^[0-9]+(\\.[0-9]+)?mm$'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.length_mm = spec.l
WHERE p.length_mm IS NULL;

-- 2) 권장 파워 용량 (W) - "450W 이상" 형태에서 숫자만
UPDATE IGNORE vga_products p
JOIN (
    SELECT product_id, MAX(CAST(REGEXP_REPLACE(spec_value, '[^0-9]', '') AS UNSIGNED)) AS w
    FROM danawa_spec_summary
    WHERE category = 'vga'
      AND spec_value REGEXP '^[0-9]+W[[:space:]]*이상$'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.recommended_psu_w = spec.w
WHERE p.recommended_psu_w IS NULL;

-- 3) 전원 커넥터 (예: "8핀 x1", "8핀 x2")
UPDATE IGNORE vga_products p
JOIN (
    SELECT s.product_id, s.spec_value AS conn, s.spec_order
    FROM danawa_spec_summary s
    WHERE s.category = 'vga' AND s.spec_key = '전원 포트'
) spec ON spec.product_id = p.product_id
JOIN (
    SELECT product_id, MIN(spec_order) AS min_order
    FROM danawa_spec_summary WHERE category = 'vga' AND spec_key = '전원 포트'
    GROUP BY product_id
) fr ON fr.product_id = spec.product_id AND fr.min_order = spec.spec_order
SET p.power_connector = spec.conn
WHERE p.power_connector IS NULL;

SELECT 'vga length_mm 채워진 개수' AS info, COUNT(*) AS cnt FROM vga_products WHERE length_mm IS NOT NULL;
SELECT 'vga recommended_psu_w 채워진 개수' AS info, COUNT(*) AS cnt FROM vga_products WHERE recommended_psu_w IS NOT NULL;
SELECT 'vga power_connector 채워진 개수' AS info, COUNT(*) AS cnt FROM vga_products WHERE power_connector IS NOT NULL;

-- ============================================================
-- Power(파워) 정격출력 / 폼팩터 채우기
-- 전제조건: add_compat_columns.sql 실행 완료 + spec_scraper.py --category power 완료
-- 실제 형태:
--   정격출력: spec_key = "출력 용량(W)" 인 경우가 많지만, spec_key가 NULL이고
--             spec_value가 순수하게 "500W" 형태인 행도 많음 -> 둘 다 커버.
--             ("출력 용량(VA)"는 다른 단위라 제외, "대기전력 1W 미만"처럼
--              부가 텍스트가 붙은 값은 정규식으로 자동 제외됨)
--   폼팩터:   spec_key는 보통 NULL, spec_value가 "ATX 파워", "M-ATX(SFX) 파워",
--             "Flex-ATX 파워"처럼 반드시 "파워"로 끝남 (인증 변경이력 텍스트와 구분되는 지점)
-- ============================================================
USE DW_db;
SET SQL_SAFE_UPDATES = 0;
-- 1) 정격 출력 (W)
UPDATE IGNORE power_products p
JOIN (
    SELECT product_id,
           MAX(CAST(REPLACE(spec_value, 'W', '') AS UNSIGNED)) AS w
    FROM danawa_spec_summary
    WHERE category = 'power'
      AND (spec_key = '출력 용량(W)' OR spec_key IS NULL)
      AND spec_value REGEXP '^[0-9]+W$'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.rated_w = spec.w
WHERE p.rated_w IS NULL;

-- 2) 폼팩터 ("...파워"로 끝나는 행만 사용 - 인증서 변경이력 등 노이즈 자동 배제)
UPDATE IGNORE power_products p
JOIN (
    SELECT s.product_id,
           CASE
               WHEN s.spec_value LIKE '%SFX%'      THEN 'SFX'
               WHEN s.spec_value LIKE '%TFX%'       THEN 'TFX'
               WHEN s.spec_value LIKE '%Flex-ATX%' OR s.spec_value LIKE '%FLEX%' THEN 'FLEX'
               ELSE 'ATX'
           END AS ff,
           s.spec_order
    FROM danawa_spec_summary s
    WHERE s.category = 'power'
      AND s.spec_value LIKE '%파워'
) spec ON spec.product_id = p.product_id
JOIN (
    SELECT product_id, MIN(spec_order) AS min_order
    FROM danawa_spec_summary WHERE category = 'power' AND spec_value LIKE '%파워'
    GROUP BY product_id
) fr ON fr.product_id = spec.product_id AND fr.min_order = spec.spec_order
SET p.form_factor = spec.ff
WHERE p.form_factor IS NULL;

SELECT 'power rated_w 채워진 개수' AS info, COUNT(*) AS cnt FROM power_products WHERE rated_w IS NOT NULL;
SELECT 'power form_factor 채워진 개수' AS info, COUNT(*) AS cnt FROM power_products WHERE form_factor IS NOT NULL;
SELECT form_factor, COUNT(*) cnt FROM power_products GROUP BY form_factor ORDER BY cnt DESC;

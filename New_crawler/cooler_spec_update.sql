-- ============================================================
-- Cooler 지원 소켓 / 높이 채우기
-- 전제조건: add_compat_columns.sql 실행 완료 + spec_scraper.py --category cooler 완료
-- 실제 형태:
--   지원 소켓: spec_key = "인텔 소켓" 또는 "AMD 소켓", spec_value = "LGA1200, LGA115x, LGA1366" (콤마구분)
--   높이:      spec_key = "높이", spec_value = "125mm"
-- ============================================================
USE DW_db;
SET SQL_SAFE_UPDATES = 0;
-- 1) 지원 소켓: 인텔/AMD 소켓 행을 한 상품당 하나의 콤마 문자열로 합침
UPDATE IGNORE cooler_products p
JOIN (
    SELECT product_id,
           GROUP_CONCAT(DISTINCT spec_value SEPARATOR ', ') AS sockets
    FROM danawa_spec_summary
    WHERE category = 'cooler'
      AND spec_key IN ('인텔 소켓', 'AMD 소켓')
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.support_sockets = spec.sockets
WHERE p.support_sockets IS NULL;

-- 2) 높이 (mm)
UPDATE IGNORE cooler_products p
JOIN (
    SELECT product_id, MIN(CAST(REPLACE(spec_value, 'mm', '') AS UNSIGNED)) AS h
    FROM danawa_spec_summary
    WHERE category = 'cooler'
      AND spec_key = '높이'
      AND spec_value REGEXP '^[0-9]+(\\.[0-9]+)?mm$'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.height_mm = spec.h
WHERE p.height_mm IS NULL;

SELECT 'cooler support_sockets 채워진 개수' AS info, COUNT(*) AS cnt FROM cooler_products WHERE support_sockets IS NOT NULL;
SELECT 'cooler height_mm 채워진 개수' AS info, COUNT(*) AS cnt FROM cooler_products WHERE height_mm IS NOT NULL;

-- 참고: 일체형 수랭 쿨러는 "높이"가 아니라 라디에이터 규격으로 표시되는 경우가 많아
-- height_mm이 비어있을 수 있음(수랭은 원래 "쿨러 높이 ≤ 케이스 최대 쿨러높이" 체크 대상이 아님).

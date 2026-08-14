-- ============================================================
-- Case 지원 폼팩터 / 최대 쿨러높이 / 최대 VGA길이 / 지원 파워규격 채우기
-- 전제조건: add_compat_columns.sql 실행 완료 + spec_scraper.py --category case 완료
-- 실제 형태:
--   지원 폼팩터: spec_key = "지원보드규격", spec_value = "ATX, M-ATX" 등 (이미 콤마로 합쳐진 문자열)
--   최대쿨러높이: spec_key = "CPU쿨러 높이", spec_value = "최대 200mm"
--   지원 파워규격: spec_key = "지원파워규격", spec_value = "표준-ATX", "M-ATX(SFX)" 등
--   최대VGA길이: 정확한 spec_key를 확인 못해서, "그래픽카드"가 들어간 key + mm값 있는 행을 넓게 잡음
--                (혹시 0건이면 discovery_spec_keys.sql의 VGA 관련 case 쿼리 결과를 다시 보내주세요)
-- ============================================================
USE DW_db;
SET SQL_SAFE_UPDATES = 0;
-- 1) 지원 보드 폼팩터 (한 상품에 여러 행이 있을 수 있어 spec_order가 가장 앞선 것 사용)
UPDATE IGNORE case_products p
JOIN (
    SELECT s.product_id, s.spec_value AS ff, s.spec_order
    FROM danawa_spec_summary s
    WHERE s.category = 'case' AND s.spec_key = '지원보드규격'
) spec ON spec.product_id = p.product_id
JOIN (
    SELECT product_id, MIN(spec_order) AS min_order
    FROM danawa_spec_summary WHERE category = 'case' AND spec_key = '지원보드규격'
    GROUP BY product_id
) fr ON fr.product_id = spec.product_id AND fr.min_order = spec.spec_order
SET p.support_form_factors = spec.ff
WHERE p.support_form_factors IS NULL;

-- 2) 최대 CPU쿨러 장착 높이 (mm)
UPDATE IGNORE case_products p
JOIN (
    SELECT product_id,
           MIN(CAST(REGEXP_REPLACE(spec_value, '[^0-9]', '') AS UNSIGNED)) AS h
    FROM danawa_spec_summary
    WHERE category = 'case' AND spec_key = 'CPU쿨러 높이'
      AND spec_value REGEXP '[0-9]+mm'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.max_cooler_height_mm = spec.h
WHERE p.max_cooler_height_mm IS NULL;

-- 3) 지원 파워 규격 (원문 그대로 저장, ATX/SFX 여부는 매칭 단계에서 문자열로 판단)
UPDATE IGNORE case_products p
JOIN (
    SELECT s.product_id, s.spec_value AS pf, s.spec_order
    FROM danawa_spec_summary s
    WHERE s.category = 'case' AND s.spec_key = '지원파워규격'
) spec ON spec.product_id = p.product_id
JOIN (
    SELECT product_id, MIN(spec_order) AS min_order
    FROM danawa_spec_summary WHERE category = 'case' AND spec_key = '지원파워규격'
    GROUP BY product_id
) fr ON fr.product_id = spec.product_id AND fr.min_order = spec.spec_order
SET p.support_psu_form_factors = spec.pf
WHERE p.support_psu_form_factors IS NULL;

-- 4) 최대 VGA 길이 (mm) - 정확한 spec_key 미확인이라 넓게 잡음
UPDATE IGNORE case_products p
JOIN (
    SELECT product_id,
           MAX(CAST(REGEXP_REPLACE(spec_value, '[^0-9]', '') AS UNSIGNED)) AS l
    FROM danawa_spec_summary
    WHERE category = 'case'
      AND (spec_key LIKE '%그래픽카드%' OR spec_key LIKE '%VGA%')
      AND spec_value REGEXP '[0-9]+mm'
    GROUP BY product_id
) spec ON spec.product_id = p.product_id
SET p.max_vga_length_mm = spec.l
WHERE p.max_vga_length_mm IS NULL;

SELECT 'case support_form_factors 채워진 개수' AS info, COUNT(*) AS cnt FROM case_products WHERE support_form_factors IS NOT NULL;
SELECT 'case max_cooler_height_mm 채워진 개수' AS info, COUNT(*) AS cnt FROM case_products WHERE max_cooler_height_mm IS NOT NULL;
SELECT 'case support_psu_form_factors 채워진 개수' AS info, COUNT(*) AS cnt FROM case_products WHERE support_psu_form_factors IS NOT NULL;
SELECT 'case max_vga_length_mm 채워진 개수 (0건이면 discovery 결과 다시 확인 필요)' AS info, COUNT(*) AS cnt FROM case_products WHERE max_vga_length_mm IS NOT NULL;

-- ============================================================
-- (별도 실행) CPU 내장그래픽 유무 / PBP-MTP(최소-최대 전력) 채우기 - v3
-- 전제조건:
--   1) 위 danawa_only_load.sql 이 먼저 실행되어 cpu_products 가 존재해야 함
--   2) spec_scraper.py --category cpu 를 실행해서 danawa_spec_summary 테이블에
--      CPU 상세페이지 요약정보가 쌓여 있어야 함
--
-- v3 변경점:
--   - UPDATE IGNORE 로 감싸서, 특정 상품 하나가 이상한 값이어도 전체가 멈추지 않게 함
--   - 파싱된 전력값이 1~2000W 범위를 벗어나면 이상치로 보고 NULL 처리 (오탐 방지)
--   - AMD TDP-only(=PPT 표기 없는 구형/저전력 모델, 일부 구형 인텔도 TDP만 있음)도
--     LEFT JOIN 으로 처리해서 놓치지 않도록 함
-- ============================================================
USE DW_db;

-- 1) 내장그래픽 유무
UPDATE IGNORE cpu_products p
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
UPDATE IGNORE cpu_products p
JOIN (
    SELECT product_id,
           CAST(SUBSTRING_INDEX(REGEXP_REPLACE(spec_value, '[^0-9-]', ''), '-', 1) AS UNSIGNED) AS pmin_raw,
           CAST(SUBSTRING_INDEX(REGEXP_REPLACE(spec_value, '[^0-9-]', ''), '-', -1) AS UNSIGNED) AS pmax_raw
    FROM danawa_spec_summary
    WHERE category = 'cpu'
      AND spec_key LIKE '%PBP%'
      AND spec_value REGEXP '^[0-9]+[[:space:]]*-[[:space:]]*[0-9]+'
) spec ON spec.product_id = p.product_id
SET p.power_min_w = CASE WHEN spec.pmin_raw BETWEEN 1 AND 2000 THEN spec.pmin_raw ELSE NULL END,
    p.power_max_w = CASE WHEN spec.pmax_raw BETWEEN 1 AND 2000 THEN spec.pmax_raw ELSE NULL END
WHERE p.power_min_w IS NULL;

-- 3) 전력(TDP/PPT 방식: AMD는 TDP=최소/PPT=최대, 일부 구형 인텔은 TDP만 단독으로 존재)
UPDATE IGNORE cpu_products p
JOIN (
    SELECT t.product_id,
           CAST(REGEXP_REPLACE(t.spec_value, '[^0-9]', '') AS UNSIGNED) AS tdp_raw,
           CAST(REGEXP_REPLACE(pp.spec_value, '[^0-9]', '') AS UNSIGNED) AS ppt_raw
    FROM danawa_spec_summary t
    LEFT JOIN danawa_spec_summary pp
      ON pp.category = 'cpu' AND pp.product_id = t.product_id AND pp.spec_key LIKE '%PPT%'
    WHERE t.category = 'cpu'
      AND t.spec_key LIKE '%TDP%'
) spec ON spec.product_id = p.product_id
SET p.power_min_w = CASE WHEN spec.tdp_raw BETWEEN 1 AND 2000 THEN spec.tdp_raw ELSE NULL END,
    p.power_max_w = CASE
                        WHEN spec.ppt_raw BETWEEN 1 AND 2000 THEN spec.ppt_raw
                        WHEN spec.tdp_raw BETWEEN 1 AND 2000 THEN spec.tdp_raw
                        ELSE NULL
                    END
WHERE p.power_min_w IS NULL;

SELECT 'cpu has_igpu 채워진 개수' AS info, COUNT(*) AS cnt FROM cpu_products WHERE has_igpu IS NOT NULL;
SELECT 'cpu power_min_w/power_max_w 채워진 개수' AS info, COUNT(*) AS cnt FROM cpu_products WHERE power_min_w IS NOT NULL;

-- 혹시 여전히 비어있는데 TDP/PBP-MTP 키는 있는 상품이 있다면, 실제 값 형태를 눈으로 확인:
-- SELECT p.product_id, p.name, s.spec_key, s.spec_value
-- FROM cpu_products p
-- JOIN danawa_spec_summary s ON s.category='cpu' AND s.product_id=p.product_id
--      AND (s.spec_key LIKE '%TDP%' OR s.spec_key LIKE '%PBP%')
-- WHERE p.power_min_w IS NULL;

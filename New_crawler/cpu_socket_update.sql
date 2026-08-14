-- ============================================================
-- CPU 소켓 채우기
-- 전제조건: add_compat_columns.sql 실행 완료 + spec_scraper.py --category cpu 완료
-- 실제 형태: spec_key는 NULL, spec_value가 "인텔(소켓775)", "AMD(소켓AM4)" 형식.
--            같은 상품에 "AMD 라데온 Vega 3" 같은 무관한 행도 섞여있으므로
--            "(소켓" 문자열이 포함된 행만 골라서 사용.
-- ============================================================
USE DW_db;
SET SQL_SAFE_UPDATES = 0;

UPDATE IGNORE cpu_products p
JOIN (
    SELECT
        s.product_id,
        -- 괄호 안에서 "소켓" 글자를 뗀 나머지.
        -- 숫자만 남으면(인텔) 앞에 LGA를 붙이고, 문자가 섞여있으면(AMD, AM4/AM5/TR4 등) 그대로 사용.
        CASE
            WHEN REGEXP_REPLACE(REGEXP_SUBSTR(s.spec_value, '\\([^)]*\\)'), '[()소켓]', '') REGEXP '^[0-9]+$'
                THEN CONCAT('LGA', REGEXP_REPLACE(REGEXP_SUBSTR(s.spec_value, '\\([^)]*\\)'), '[()소켓]', ''))
            ELSE UPPER(REGEXP_REPLACE(REGEXP_SUBSTR(s.spec_value, '\\([^)]*\\)'), '[()소켓]', ''))
        END AS socket_value,
        s.spec_order
    FROM danawa_spec_summary s
    WHERE s.category = 'cpu'
      AND s.spec_value LIKE '%(소켓%'
) spec ON spec.product_id = p.product_id
-- 한 상품에 소켓 행이 여러 개 나올 수 있어(예: 하위호환 소켓 안내) spec_order가 가장 앞선 것 하나만 사용
JOIN (
    SELECT product_id, MIN(spec_order) AS min_order
    FROM danawa_spec_summary
    WHERE category = 'cpu' AND spec_value LIKE '%(소켓%'
    GROUP BY product_id
) first_row ON first_row.product_id = spec.product_id AND first_row.min_order = spec.spec_order
SET p.socket = spec.socket_value
WHERE p.socket IS NULL;

SELECT 'cpu socket 채워진 개수' AS info, COUNT(*) AS cnt FROM cpu_products WHERE socket IS NOT NULL;

-- 확인: 어떤 소켓 값들이 채워졌는지
SELECT socket, COUNT(*) AS cnt FROM cpu_products GROUP BY socket ORDER BY cnt DESC;

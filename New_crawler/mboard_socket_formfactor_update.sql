-- ============================================================
-- MBoard 소켓 / 폼팩터 / RAM 규격 채우기
-- 전제조건: add_compat_columns.sql 실행 완료 + spec_scraper.py --category mboard 완료
-- ============================================================
USE DW_db;
SET SQL_SAFE_UPDATES = 0;
-- 1) 소켓 (CPU와 동일한 "제조사(소켓XXXX)" 형식)
UPDATE IGNORE mboard_products p
JOIN (
    SELECT
        s.product_id,
        CASE
            WHEN REGEXP_REPLACE(REGEXP_SUBSTR(s.spec_value, '\\([^)]*\\)'), '[()소켓]', '') REGEXP '^[0-9]+$'
                THEN CONCAT('LGA', REGEXP_REPLACE(REGEXP_SUBSTR(s.spec_value, '\\([^)]*\\)'), '[()소켓]', ''))
            ELSE UPPER(REGEXP_REPLACE(REGEXP_SUBSTR(s.spec_value, '\\([^)]*\\)'), '[()소켓]', ''))
        END AS socket_value,
        s.spec_order
    FROM danawa_spec_summary s
    WHERE s.category = 'mboard'
      AND s.spec_value LIKE '%(소켓%'
) spec ON spec.product_id = p.product_id
JOIN (
    SELECT product_id, MIN(spec_order) AS min_order
    FROM danawa_spec_summary
    WHERE category = 'mboard' AND spec_value LIKE '%(소켓%'
    GROUP BY product_id
) first_row ON first_row.product_id = spec.product_id AND first_row.min_order = spec.spec_order
SET p.socket = spec.socket_value
WHERE p.socket IS NULL;

-- 2) 폼팩터 ("ATX (30.5x24.4cm)" -> "ATX", "M-ITX (17.0x17.0cm)" -> "M-ITX")
UPDATE IGNORE mboard_products p
JOIN (
    SELECT s.product_id, TRIM(SUBSTRING_INDEX(s.spec_value, '(', 1)) AS ff, s.spec_order
    FROM danawa_spec_summary s
    WHERE s.category = 'mboard'
      AND s.spec_value REGEXP '^(E-ATX|ATX|M-ATX|M-ITX|ITX|Pico-ITX)[[:space:]]*\\('
) spec ON spec.product_id = p.product_id
JOIN (
    SELECT product_id, MIN(spec_order) AS min_order
    FROM danawa_spec_summary
    WHERE category = 'mboard'
      AND spec_value REGEXP '^(E-ATX|ATX|M-ATX|M-ITX|ITX|Pico-ITX)[[:space:]]*\\('
    GROUP BY product_id
) first_row ON first_row.product_id = spec.product_id AND first_row.min_order = spec.spec_order
SET p.form_factor = spec.ff
WHERE p.form_factor IS NULL;

-- 3) RAM 규격 (DDR4 / DDR5, "노트북용" 접미사는 무시하고 앞 부분만 사용)
UPDATE IGNORE mboard_products p
JOIN (
    SELECT s.product_id, REGEXP_SUBSTR(s.spec_value, '^(DDR4|DDR5|LPDDR4|LPDDR5)') AS rtype, s.spec_order
    FROM danawa_spec_summary s
    WHERE s.category = 'mboard'
      AND s.spec_value REGEXP '^(DDR4|DDR5|LPDDR4|LPDDR5)'
) spec ON spec.product_id = p.product_id
JOIN (
    SELECT product_id, MIN(spec_order) AS min_order
    FROM danawa_spec_summary
    WHERE category = 'mboard' AND spec_value REGEXP '^(DDR4|DDR5|LPDDR4|LPDDR5)'
    GROUP BY product_id
) first_row ON first_row.product_id = spec.product_id AND first_row.min_order = spec.spec_order
SET p.ram_type = spec.rtype
WHERE p.ram_type IS NULL;

SELECT 'mboard socket 채워진 개수' AS info, COUNT(*) AS cnt FROM mboard_products WHERE socket IS NOT NULL;
SELECT 'mboard form_factor 채워진 개수' AS info, COUNT(*) AS cnt FROM mboard_products WHERE form_factor IS NOT NULL;
SELECT 'mboard ram_type 채워진 개수' AS info, COUNT(*) AS cnt FROM mboard_products WHERE ram_type IS NOT NULL;

SELECT socket, COUNT(*) cnt FROM mboard_products GROUP BY socket ORDER BY cnt DESC;
SELECT form_factor, COUNT(*) cnt FROM mboard_products GROUP BY form_factor ORDER BY cnt DESC;
SELECT ram_type, COUNT(*) cnt FROM mboard_products GROUP BY ram_type ORDER BY cnt DESC;

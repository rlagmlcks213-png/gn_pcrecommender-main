USE DW_db;

-- ---------- RAM 용량 (RGB 관련 spec_key 제외) ----------
SELECT DISTINCT spec_key, spec_value
FROM danawa_spec_summary
WHERE category = 'ram'
  AND spec_value REGEXP '[0-9]GB'
  AND spec_key NOT LIKE '%LED%'
  AND spec_value NOT LIKE '%RGB%'
  AND spec_value NOT LIKE '%SYNC%'
  AND spec_value NOT LIKE '%FUSION%'
  AND spec_value NOT LIKE '%LIGHT%'
LIMIT 40;

-- ---------- SSD 용량 (조건 완화: spec_key 상관없이, TB/GB 포함되면 전부 - 앞뒤로 뭐가 붙어있는지 확인용) ----------
SELECT DISTINCT spec_key, spec_value
FROM danawa_spec_summary
WHERE category = 'ssd'
  AND (spec_value REGEXP '[0-9](GB|TB)' )
LIMIT 60;

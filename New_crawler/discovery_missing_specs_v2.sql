USE DW_db;

-- ---------- RAM 용량 (조건 완화: GB가 포함되기만 하면 다 보기) ----------
SELECT DISTINCT spec_key, spec_value
FROM danawa_spec_summary
WHERE category = 'ram'
  AND spec_value LIKE '%GB%'
LIMIT 40;

-- ---------- SSD 실제 저장용량 (TBW/SLC/DDR 버퍼 제외하고 순수 용량만) ----------
SELECT DISTINCT spec_key, spec_value
FROM danawa_spec_summary
WHERE category = 'ssd'
  AND spec_key IS NULL
  AND spec_value REGEXP '^[0-9]+(GB|TB)$'
  AND spec_value NOT LIKE 'DDR%'
LIMIT 40;

-- ---------- Case 팬/라디에이터 장착 위치 전체 목록 (spec_key별로 어떤 위치들이 있는지) ----------
SELECT DISTINCT spec_key
FROM danawa_spec_summary
WHERE category = 'case'
  AND spec_value REGEXP 'mm'
ORDER BY spec_key;

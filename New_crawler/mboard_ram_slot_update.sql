-- ============================================================
-- (별도 실행/재실행 가능) 메인보드 RAM 소켓(슬롯) 개수 채우기 - v2
-- 실제 저장 형태 확인 결과: 슬롯 개수는 spec_key가 NULL이고,
-- "[메모리]" 라는 섹션 표시 바로 다음에 "N개" 형태의 값으로만 존재함.
-- (예: NULL|[메모리] -> NULL|1600MHz(PC3-12800) -> NULL|4개 -> 메모리 용량|최대 32GB)
-- 그래서 "[메모리]" 섹션이 시작되는 지점(spec_order)과, 그 다음 "[...]" 섹션이
-- 시작되는 지점 "사이"에 있는 값들 중 "숫자+개" 형태를 슬롯 개수로 판단합니다.
-- 전제조건: danawa_only_load.sql + spec_scraper.py --category mboard 먼저 실행되어 있어야 함
-- ============================================================
USE DW_db;

DROP TEMPORARY TABLE IF EXISTS tmp_mem_section;
CREATE TEMPORARY TABLE tmp_mem_section AS
SELECT product_id, MIN(spec_order) AS mem_start
FROM danawa_spec_summary
WHERE category = 'mboard' AND spec_value = '[메모리]'
GROUP BY product_id;

DROP TEMPORARY TABLE IF EXISTS tmp_next_section;
CREATE TEMPORARY TABLE tmp_next_section AS
SELECT s.product_id, MIN(s.spec_order) AS next_start
FROM danawa_spec_summary s
JOIN tmp_mem_section ms ON ms.product_id = s.product_id
WHERE s.category = 'mboard'
  AND s.spec_value LIKE '[%]'
  AND s.spec_order > ms.mem_start
GROUP BY s.product_id;

DROP TEMPORARY TABLE IF EXISTS tmp_ram_slot;
CREATE TEMPORARY TABLE tmp_ram_slot AS
SELECT m.product_id,
       CAST(REPLACE(m.spec_value, '개', '') AS UNSIGNED) AS slots
FROM danawa_spec_summary m
JOIN tmp_mem_section ms ON ms.product_id = m.product_id
LEFT JOIN tmp_next_section ns ON ns.product_id = m.product_id
WHERE m.category = 'mboard'
  AND m.spec_order > ms.mem_start
  AND (ns.next_start IS NULL OR m.spec_order < ns.next_start)
  AND m.spec_value REGEXP '^[0-9]+개$';

UPDATE mboard_products p
JOIN tmp_ram_slot t ON t.product_id = p.product_id
SET p.ram_slot_count = t.slots;

SELECT 'mboard ram_slot_count 채워진 개수' AS info, COUNT(*) AS cnt
FROM mboard_products WHERE ram_slot_count IS NOT NULL;

DROP TEMPORARY TABLE IF EXISTS tmp_mem_section;
DROP TEMPORARY TABLE IF EXISTS tmp_next_section;
DROP TEMPORARY TABLE IF EXISTS tmp_ram_slot;

-- 그래도 0건이면 아래로 실제 [메모리] 섹션 부분을 직접 확인해서 알려주세요.
-- SELECT spec_order, spec_key, spec_value FROM danawa_spec_summary
-- WHERE category='mboard' AND product_id=(SELECT product_id FROM mboard_products LIMIT 1)
-- ORDER BY spec_order;

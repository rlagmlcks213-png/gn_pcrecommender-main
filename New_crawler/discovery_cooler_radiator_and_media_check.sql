USE DW_db;

-- ---------- 1) 쿨러 라디에이터 관련 spec_key 후보 ----------
SELECT DISTINCT spec_key, spec_value
FROM danawa_spec_summary
WHERE category = 'cooler'
  AND (spec_key LIKE '%라디에이터%' OR spec_value LIKE '%라디에이터%'
       OR spec_key LIKE '%냉각%' OR spec_value REGEXP '(240|280|360|420)mm')
LIMIT 40;

-- ---------- 2) 쿨러 냉각방식(공랭/수랭) 구분 후보 ----------
SELECT DISTINCT spec_key, spec_value
FROM danawa_spec_summary
WHERE category = 'cooler'
  AND (spec_key LIKE '%방식%' OR spec_value LIKE '%공랭%' OR spec_value LIKE '%수랭%' OR spec_value LIKE '%일체형%')
LIMIT 30;

-- ---------- 3) product_media 전체 카테고리 커버리지 확인 (사진/링크 어디까지 됐는지) ----------
SELECT 'cpu' t, COUNT(*) AS media_cnt, (SELECT COUNT(*) FROM cpu_products) AS product_cnt FROM product_media WHERE category='cpu'
UNION ALL
SELECT 'vga', COUNT(*), (SELECT COUNT(*) FROM vga_products) FROM product_media WHERE category='vga'
UNION ALL
SELECT 'mboard', COUNT(*), (SELECT COUNT(*) FROM mboard_products) FROM product_media WHERE category='mboard'
UNION ALL
SELECT 'ram', COUNT(*), (SELECT COUNT(*) FROM ram_products) FROM product_media WHERE category='ram'
UNION ALL
SELECT 'ssd', COUNT(*), (SELECT COUNT(*) FROM ssd_products) FROM product_media WHERE category='ssd'
UNION ALL
SELECT 'hdd', COUNT(*), (SELECT COUNT(*) FROM hdd_products) FROM product_media WHERE category='hdd'
UNION ALL
SELECT 'power', COUNT(*), (SELECT COUNT(*) FROM power_products) FROM product_media WHERE category='power'
UNION ALL
SELECT 'cooler', COUNT(*), (SELECT COUNT(*) FROM cooler_products) FROM product_media WHERE category='cooler'
UNION ALL
SELECT 'case', COUNT(*), (SELECT COUNT(*) FROM case_products) FROM product_media WHERE category='case';

-- ============================================================
-- 호환성 컬럼을 채우기 전에, danawa_spec_summary 에 실제로 어떤
-- spec_key / spec_value 형태로 저장되어 있는지 먼저 확인하는 스크립트.
--
-- 사용법:
--   1) 아래 카테고리들에 대해 각각 spec_scraper.py 를 미리 실행해서
--      danawa_spec_summary 에 데이터를 쌓아둡니다.
--        python spec_scraper.py --category cpu
--        python spec_scraper.py --category mboard
--        python spec_scraper.py --category cooler
--        python spec_scraper.py --category case
--        python spec_scraper.py --category vga
--        python spec_scraper.py --category power
--        python spec_scraper.py --category ram
--   2) 이 SQL을 실행해서 나온 결과(특히 spec_key, spec_value 컬럼)를
--      그대로 캡처하거나 복사해서 알려주세요.
--   3) 그 실제 텍스트 형태를 보고, cpu_spec_update.sql / mboard_ram_slot_update.sql
--      과 같은 방식으로 정확한 추출 UPDATE 스크립트를 만들어드리겠습니다.
-- ============================================================
USE DW_db;

-- ---------- CPU: 소켓 후보 ----------
SELECT DISTINCT spec_key, spec_value
FROM danawa_spec_summary
WHERE category = 'cpu'
  AND (spec_key LIKE '%소켓%' OR spec_value LIKE '%소켓%' OR spec_value LIKE '%LGA%' OR spec_value LIKE '%AM%')
LIMIT 30;

-- ---------- MBoard: 소켓 / 폼팩터 / RAM 규격 후보 ----------
SELECT DISTINCT spec_key, spec_value
FROM danawa_spec_summary
WHERE category = 'mboard'
  AND (spec_key LIKE '%소켓%' OR spec_value LIKE '%LGA%' OR spec_value LIKE '%AM%')
LIMIT 30;

SELECT DISTINCT spec_key, spec_value
FROM danawa_spec_summary
WHERE category = 'mboard'
  AND (spec_key LIKE '%폼팩터%' OR spec_value LIKE '%ATX%' OR spec_value LIKE '%ITX%')
LIMIT 30;

SELECT DISTINCT spec_key, spec_value
FROM danawa_spec_summary
WHERE category = 'mboard'
  AND (spec_value LIKE '%DDR4%' OR spec_value LIKE '%DDR5%')
LIMIT 30;

-- ---------- RAM: 규격(DDR4/DDR5) 후보 ----------
SELECT DISTINCT spec_key, spec_value
FROM danawa_spec_summary
WHERE category = 'ram'
  AND (spec_value LIKE '%DDR4%' OR spec_value LIKE '%DDR5%')
LIMIT 30;

-- ---------- Cooler: 지원 소켓 / 높이 후보 ----------
SELECT DISTINCT spec_key, spec_value
FROM danawa_spec_summary
WHERE category = 'cooler'
  AND (spec_key LIKE '%소켓%' OR spec_value LIKE '%LGA%' OR spec_value LIKE '%AM%')
LIMIT 30;

SELECT DISTINCT spec_key, spec_value
FROM danawa_spec_summary
WHERE category = 'cooler'
  AND (spec_key LIKE '%높이%' OR spec_key LIKE '%전고%' OR spec_value LIKE '%mm%')
LIMIT 30;

-- ---------- Case: 지원 폼팩터 / 최대 쿨러높이 / 최대 VGA길이 / 파워 폼팩터 후보 ----------
SELECT DISTINCT spec_key, spec_value
FROM danawa_spec_summary
WHERE category = 'case'
  AND (spec_key LIKE '%보드규격%' OR spec_key LIKE '%지원보드%' OR spec_value LIKE '%ATX%')
LIMIT 30;

SELECT DISTINCT spec_key, spec_value
FROM danawa_spec_summary
WHERE category = 'case'
  AND (spec_key LIKE '%쿨러%' OR spec_key LIKE '%CPU%쿨러%')
LIMIT 30;

SELECT DISTINCT spec_key, spec_value
FROM danawa_spec_summary
WHERE category = 'case'
  AND (spec_key LIKE '%그래픽카드%' OR spec_key LIKE '%VGA%')
LIMIT 30;

SELECT DISTINCT spec_key, spec_value
FROM danawa_spec_summary
WHERE category = 'case'
  AND (spec_key LIKE '%파워%' OR spec_value LIKE '%SFX%')
LIMIT 30;

-- ---------- VGA: 길이 / 전력 / 커넥터 후보 ----------
SELECT DISTINCT spec_key, spec_value
FROM danawa_spec_summary
WHERE category = 'vga'
  AND (spec_key LIKE '%길이%' OR spec_key LIKE '%크기%' OR spec_value LIKE '%mm%')
LIMIT 30;

SELECT DISTINCT spec_key, spec_value
FROM danawa_spec_summary
WHERE category = 'vga'
  AND (spec_key LIKE '%전원%' OR spec_key LIKE '%파워%' OR spec_value LIKE '%W%')
LIMIT 30;

-- ---------- Power: 정격출력 / 폼팩터 후보 ----------
SELECT DISTINCT spec_key, spec_value
FROM danawa_spec_summary
WHERE category = 'power'
  AND (spec_key LIKE '%정격%' OR spec_key LIKE '%출력%' OR spec_value LIKE '%W%')
LIMIT 30;

SELECT DISTINCT spec_key, spec_value
FROM danawa_spec_summary
WHERE category = 'power'
  AND (spec_key LIKE '%폼팩터%' OR spec_key LIKE '%규격%' OR spec_value LIKE '%SFX%' OR spec_value LIKE '%ATX%')
LIMIT 30;

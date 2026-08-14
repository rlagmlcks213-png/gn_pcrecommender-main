-- ============================================================
-- 누락됐던 컬럼 4종 추가
--   1) RAM / SSD / HDD 용량(GB)
--   2) 쿨러 TDP 감당치(W)
--   3) 케이스 라디에이터 지원 규격 (상단/측면/후면)
-- 실행 순서: 이 파일 먼저 실행 -> 결과로 나오는 discovery 쿼리 결과를 캡처해서 보내주면
--            그 실제 텍스트 형태에 맞는 채우기(UPDATE) 스크립트를 만들어드립니다.
-- ============================================================
USE DW_db;

-- ---------- 1) 컬럼 추가 ----------
ALTER TABLE ram_products
    ADD COLUMN capacity_gb SMALLINT UNSIGNED NULL;   -- 예: 16, 32 (단일 모듈 또는 키트 총용량)

ALTER TABLE ssd_products
    ADD COLUMN capacity_gb INT UNSIGNED NULL;        -- 예: 500, 1000, 2000

ALTER TABLE hdd_products
    ADD COLUMN capacity_gb INT UNSIGNED NULL;        -- 예: 1000, 2000, 4000

ALTER TABLE cooler_products
    ADD COLUMN tdp_rating_w SMALLINT UNSIGNED NULL;  -- 감당 가능 TDP(W)

ALTER TABLE case_products
    ADD COLUMN radiator_top_mm   VARCHAR(50) NULL,   -- 상단 라디에이터 지원 규격 (예: "240,280,360")
    ADD COLUMN radiator_side_mm  VARCHAR(50) NULL,   -- 측면 라디에이터 지원 규격
    ADD COLUMN radiator_rear_mm  VARCHAR(50) NULL;   -- 후면 라디에이터 지원 규격

SELECT '컬럼 추가 완료. 아래 discovery 쿼리 결과들을 캡처해서 보내주세요.' AS next_step;

-- ============================================================
-- 2) Discovery: 실제 spec_key / spec_value 형태 확인
-- ============================================================

-- ---------- RAM 용량 후보 ----------
SELECT DISTINCT spec_key, spec_value
FROM danawa_spec_summary
WHERE category = 'ram'
  AND (spec_key LIKE '%용량%' OR spec_value REGEXP '^[0-9]+GB$')
LIMIT 30;

-- ---------- SSD 용량 후보 ----------
SELECT DISTINCT spec_key, spec_value
FROM danawa_spec_summary
WHERE category = 'ssd'
  AND (spec_key LIKE '%용량%' OR spec_value REGEXP '[0-9]+(GB|TB)')
LIMIT 30;

-- ---------- HDD 용량 후보 ----------
SELECT DISTINCT spec_key, spec_value
FROM danawa_spec_summary
WHERE category = 'hdd'
  AND (spec_key LIKE '%용량%' OR spec_value REGEXP '[0-9]+(GB|TB)')
LIMIT 30;

-- ---------- Cooler TDP 후보 ----------
SELECT DISTINCT spec_key, spec_value
FROM danawa_spec_summary
WHERE category = 'cooler'
  AND (spec_key LIKE '%TDP%' OR spec_key LIKE '%출력%' OR spec_value LIKE '%TDP%' OR spec_value REGEXP '[0-9]+W')
LIMIT 30;

-- ---------- Case 라디에이터 후보 ----------
SELECT DISTINCT spec_key, spec_value
FROM danawa_spec_summary
WHERE category = 'case'
  AND (spec_key LIKE '%라디에이터%' OR spec_value LIKE '%라디에이터%' OR spec_value LIKE '%mm 이하%'
       OR spec_value REGEXP '(240|280|360|120|140)')
LIMIT 50;

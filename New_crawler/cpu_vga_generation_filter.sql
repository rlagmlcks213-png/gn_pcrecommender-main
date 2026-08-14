-- ============================================================
-- CPU: 13/14세대 + 코어 울트라 시리즈2(Arrow Lake)만 남기고 나머지 삭제
-- VGA: RTX 40 / RTX 50 데스크탑 게이밍 라인업만 남기고 나머지 삭제
--      (워크스테이션 RTX PRO/Quadro/A시리즈/Ada, 구형 GTX/GT, eGPU/라이저 등 액세서리 전부 제외)
-- 이미 danawa_only_load.sql로 적재 완료된 DB에 대해 사후 정리하는 스크립트.
-- performance_tier.sql은 이 스크립트 실행 "이후"에 다시 돌려야 tier_rank가 깨끗하게 채워짐.
-- ============================================================
USE DW_db;
SET SQL_SAFE_UPDATES = 0;

-- ---------- 1) CPU 정리 ----------
-- 남길 조건: "13세대" 또는 "14세대"가 들어간 코어i3/i5/i7/i9, 또는 "울트라"+"시리즈2"
-- 제외: 제온/펜티엄/셀러론/코어2 등은 13/14세대 표기가 있어도 라인업 밖이므로 제외
DELETE FROM cpu_products
WHERE NOT (
    (name LIKE '%13세대%' OR name LIKE '%14세대%' OR (name LIKE '%울트라%' AND name LIKE '%시리즈2%'))
    AND name NOT LIKE '%제온%'
    AND name NOT LIKE '%펜티엄%'
    AND name NOT LIKE '%셀러론%'
);

SELECT '정리 후 cpu_products 개수' AS info, COUNT(*) AS cnt FROM cpu_products;

-- ---------- 2) VGA 정리 ----------
-- 남길 조건: "RTX 4060/4070/4080/4090" 또는 "RTX 5050/5060/5070/5080/5090" 형태의 4자리 모델코드
-- 제외: RTX PRO / Quadro / A2000~A6000 / Ada Generation / 워크스테이션 / eGPU 독/라이저 등
DELETE FROM vga_products
WHERE NOT (
    (name REGEXP 'RTX ?4(060|070|080|090)' OR name REGEXP 'RTX ?5(050|060|070|080|090)')
    AND name NOT LIKE '%PRO%'
    AND name NOT LIKE '%Quadro%'
    AND name NOT LIKE '%쿼드로%'
    AND name NOT LIKE '%Ada Generation%'
    AND name NOT LIKE '%워크스테이션%'
    AND name NOT LIKE '%Blackwell%'
    AND name NOT REGEXP 'RTX A[0-9]{4}'
);

SELECT '정리 후 vga_products 개수' AS info, COUNT(*) AS cnt FROM vga_products;

-- ---------- 3) 삭제된 상품의 부가 데이터 정리 (선택 - 지저분한 잔여 데이터 방지) ----------
DELETE s FROM danawa_spec_summary s
LEFT JOIN cpu_products p ON s.category = 'cpu' AND s.product_id = p.product_id
WHERE s.category = 'cpu' AND p.product_id IS NULL;

DELETE s FROM danawa_spec_summary s
LEFT JOIN vga_products p ON s.category = 'vga' AND s.product_id = p.product_id
WHERE s.category = 'vga' AND p.product_id IS NULL;

-- 가격 이력 테이블도 있다면 같이 정리 (테이블명이 다르면 이 두 줄은 에러 없이 무시하고 건너뛰어도 됨)
-- DELETE pp FROM cpu_prices pp LEFT JOIN cpu_products p ON pp.product_id = p.product_id WHERE p.product_id IS NULL;
-- DELETE pp FROM vga_prices pp LEFT JOIN vga_products p ON pp.product_id = p.product_id WHERE p.product_id IS NULL;

SELECT '완료. 이제 performance_tier.sql을 다시 실행하세요 (tier_rank 재계산 필요)' AS next_step;

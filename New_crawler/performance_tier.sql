-- ============================================================
-- 부품 성능 등급 고정 순서표 (기획서 6장 기준)
-- - source='DOC'          : 기획서 6.1/6.2절에 명시적으로 위치가 나온 것
-- - source='EXTRAPOLATED' : 기획서 표에 없는 SKU(RTX 5050, 코어 울트라 다수 모델)를
--                           문서의 원칙(체급우선+세대보완 / 라인업체급+K+세대역전)을
--                           그대로 적용해 제가 추정한 위치. 반드시 팀원 검토 필요.
-- 실행 순서: danawa_only_load.sql + spec_update.sql들 다 끝난 뒤 아무 때나 실행 가능
--            (cpu_products / vga_products 존재만 하면 됨)
-- ============================================================
USE DW_db;
SET SQL_SAFE_UPDATES = 0;

-- ---------- 1) 등급표 테이블 ----------
DROP TABLE IF EXISTS cpu_performance_tier;
CREATE TABLE cpu_performance_tier (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    tier_rank   INT NOT NULL,           -- 낮을수록 하위 등급, 같은 숫자면 동급
    lineup      VARCHAR(10) NOT NULL,   -- i3 / i5 / i7 / i9
    keyword     VARCHAR(30) NOT NULL,   -- product name에 이 문자열이 포함되면 매칭 (대소문자 무시)
    source      VARCHAR(15) NOT NULL,   -- DOC / EXTRAPOLATED
    note        VARCHAR(200)
);

INSERT INTO cpu_performance_tier (tier_rank, lineup, keyword, source, note) VALUES
(1,  'i3', '13100', 'DOC', '기획서 6.2 i3 계열'),
(2,  'i3', '14100', 'DOC', '기획서 6.2 i3 계열'),
(3,  'i5', '13400', 'DOC', '기획서 6.2 i5 계열'),
(3,  'i5', '14400', 'DOC', '기획서 6.2 i5 계열 (13400과 동급)'),
(4,  'i5', '13500', 'DOC', '기획서 6.2 i5 계열'),
(4,  'i5', '14500', 'DOC', '기획서 6.2 i5 계열 (13500과 동급)'),
(5,  'i5', '225',   'EXTRAPOLATED', '울트라5 시리즈2 225(+F/T) - 문서표 245K보다 하위로 추정'),
(6,  'i5', '235',   'EXTRAPOLATED', '울트라5 시리즈2 235(+T)'),
(7,  'i5', '245',   'EXTRAPOLATED', '울트라5 시리즈2 245 (비K)'),
(8,  'i5', '245K',  'DOC', '기획서 6.2 명시: 13500/14500 위, 13600K/14600K 아래'),
(9,  'i5', '250K Plus', 'EXTRAPOLATED', '울트라5 250K/KF Plus - 245K보다 상위 추정(모델번호+Plus리프레시)'),
(10, 'i5', '13600K', 'DOC', '기획서 6.2 i5 계열'),
(10, 'i5', '14600K', 'DOC', '기획서 6.2 i5 계열 (13600K와 동급)'),
(11, 'i7', '13700',  'DOC', '기획서 6.2 i7 계열'),
(12, 'i7', '265',    'EXTRAPOLATED', '울트라7 시리즈2 265(+F/T) 비K'),
(13, 'i7', '265K',   'DOC', '기획서 6.2 명시: 13700 위, 14700 아래'),
(14, 'i7', '270K Plus', 'EXTRAPOLATED', '울트라7 270K/KF Plus - 265K보다 상위 추정'),
(15, 'i7', '14700',  'DOC', '기획서 6.2 i7 계열'),
(16, 'i7', '13700K', 'DOC', '기획서 6.2 i7 계열'),
(17, 'i7', '14700K', 'DOC', '기획서 6.2 i7 계열'),
(18, 'i9', '13900',  'DOC', '기획서 6.2 i9 계열'),
(19, 'i9', '285',    'EXTRAPOLATED', '울트라9 시리즈2 285(+T) 비K'),
(20, 'i9', '285K',   'DOC', '기획서 6.2 명시: 13900 위, 14900 아래'),
(21, 'i9', '14900',  'DOC', '기획서 6.2 i9 계열'),
(22, 'i9', '13900K', 'DOC', '기획서 6.2 i9 계열'),
(23, 'i9', '14900K', 'DOC', '기획서 6.2 i9 계열'),
(24, 'i9', '14900KS','DOC', '기획서 6.2 i9 계열 최상위');

DROP TABLE IF EXISTS gpu_performance_tier;
CREATE TABLE gpu_performance_tier (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    tier_rank   INT NOT NULL,
    tier_group  VARCHAR(20) NOT NULL,   -- entry / high-end / flagship
    keyword     VARCHAR(30) NOT NULL,
    source      VARCHAR(15) NOT NULL,
    note        VARCHAR(200)
);

INSERT INTO gpu_performance_tier (tier_rank, tier_group, keyword, source, note) VALUES
(1,  'entry',    'RTX 5050',      'EXTRAPOLATED', '문서표에 없는 최신 엔트리 - 4060/5060보다 하위 체급으로 추정'),
(2,  'entry',    'RTX 4060',      'DOC', '기획서 6.1 엔트리/메인스트림'),
(3,  'entry',    'RTX 5060',      'DOC', '기획서 6.1 엔트리/메인스트림'),
(4,  'entry',    'RTX 4060 Ti',   'DOC', '기획서 6.1 엔트리/메인스트림'),
(5,  'entry',    'RTX 5060 Ti',   'DOC', '기획서 6.1 엔트리/메인스트림'),
(6,  'high-end', 'RTX 4070',      'DOC', '기획서 6.1 하이엔드'),
(7,  'high-end', 'RTX 4070 SUPER','DOC', '기획서 6.1 하이엔드'),
(8,  'high-end', 'RTX 5070',      'DOC', '기획서 6.1 하이엔드'),
(9,  'high-end', 'RTX 4070 Ti',   'DOC', '기획서 6.1 하이엔드'),
(10, 'high-end', 'RTX 5070 Ti',   'DOC', '기획서 6.1 하이엔드'),
(11, 'flagship', 'RTX 4080',      'DOC', '기획서 6.1 플래그십 (4080/4080 SUPER 동급)'),
(11, 'flagship', 'RTX 4080 SUPER','DOC', '기획서 6.1 플래그십 (4080과 동급)'),
(12, 'flagship', 'RTX 5080',      'DOC', '기획서 6.1 플래그십'),
(13, 'flagship', 'RTX 4090',      'DOC', '기획서 6.1 플래그십'),
(14, 'flagship', 'RTX 5090',      'DOC', '기획서 6.1 플래그십 최상위');

-- ---------- 2) 실제 상품에 tier_rank 매칭 ----------
ALTER TABLE cpu_products ADD COLUMN tier_rank INT NULL;
ALTER TABLE vga_products ADD COLUMN tier_rank INT NULL;

-- CPU: keyword 길이가 긴 것부터(=더 구체적인 것부터) 우선 매칭
-- 예: "13600K"가 "13600"보다 먼저 검사되어야 K/비K 오매칭이 안 남
UPDATE IGNORE cpu_products p
JOIN (
    SELECT c.product_id, t.tier_rank
    FROM cpu_products c
    JOIN cpu_performance_tier t ON UPPER(c.name) LIKE CONCAT('%', UPPER(t.keyword), '%')
    JOIN (
        SELECT c2.product_id, MAX(LENGTH(t2.keyword)) AS max_len
        FROM cpu_products c2
        JOIN cpu_performance_tier t2 ON UPPER(c2.name) LIKE CONCAT('%', UPPER(t2.keyword), '%')
        GROUP BY c2.product_id
    ) best ON best.product_id = c.product_id AND best.max_len = LENGTH(t.keyword)
) m ON m.product_id = p.product_id
SET p.tier_rank = m.tier_rank;

-- GPU: 동일 방식
UPDATE IGNORE vga_products p
JOIN (
    SELECT v.product_id, t.tier_rank
    FROM vga_products v
    JOIN gpu_performance_tier t ON UPPER(v.name) LIKE CONCAT('%', UPPER(t.keyword), '%')
    JOIN (
        SELECT v2.product_id, MAX(LENGTH(t2.keyword)) AS max_len
        FROM vga_products v2
        JOIN gpu_performance_tier t2 ON UPPER(v2.name) LIKE CONCAT('%', UPPER(t2.keyword), '%')
        GROUP BY v2.product_id
    ) best ON best.product_id = v.product_id AND best.max_len = LENGTH(t.keyword)
) m ON m.product_id = p.product_id
SET p.tier_rank = m.tier_rank;

-- ---------- 3) 검증 ----------
SELECT 'cpu tier_rank 채워진 개수' AS info, COUNT(*) AS cnt FROM cpu_products WHERE tier_rank IS NOT NULL;
SELECT 'cpu tier_rank 매칭 안 된 상품 (수동 확인 필요)' AS info, COUNT(*) AS cnt FROM cpu_products WHERE tier_rank IS NULL;
SELECT product_id, name FROM cpu_products WHERE tier_rank IS NULL;

SELECT 'vga tier_rank 채워진 개수' AS info, COUNT(*) AS cnt FROM vga_products WHERE tier_rank IS NOT NULL;
SELECT 'vga tier_rank 매칭 안 된 상품 (수동 확인 필요)' AS info, COUNT(*) AS cnt FROM vga_products WHERE tier_rank IS NULL;
SELECT product_id, name FROM vga_products WHERE tier_rank IS NULL;

-- 등급별 실제 매칭된 상품 개수 - 등급표 커버리지 확인용
SELECT t.tier_rank, t.lineup, t.keyword, COUNT(p.product_id) AS matched_cnt
FROM cpu_performance_tier t
LEFT JOIN cpu_products p ON p.tier_rank = t.tier_rank AND UPPER(p.name) LIKE CONCAT('%', UPPER(t.keyword), '%')
GROUP BY t.id, t.tier_rank, t.lineup, t.keyword
ORDER BY t.tier_rank;

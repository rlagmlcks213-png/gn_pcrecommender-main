-- ============================================================
-- cpu_performance_tier 보정판
-- 1) '250K Plus' 키워드가 실제 상품명 '250KF Plus'와 정확히 안 맞아 매칭 누락되던 버그 수정
--    (K와 Plus 사이에 F가 끼는 경우까지 잡도록 키워드를 '250K'와 '250KF Plus' 둘 다 등록)
-- 2) 기획서 6.2절 표에 없던 '13600'(K 없는 버전)을 13500/14500보다 위, 13600K보다 아래로 추정 삽입
--    -> source='EXTRAPOLATED', 팀 확인 필요
-- 기존 rank 5~24였던 부분이 전부 한 칸씩 밀려서 새로 5~25로 재번호됨(테이블 전체 재생성)
-- performance_tier.sql을 이미 돌리셨다면, 이 파일만 다시 실행하면 됩니다 (gpu_performance_tier는 안 건드림)
-- ============================================================
USE DW_db;
SET SQL_SAFE_UPDATES = 0;

DROP TABLE IF EXISTS cpu_performance_tier;
CREATE TABLE cpu_performance_tier (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    tier_rank   INT NOT NULL,
    lineup      VARCHAR(10) NOT NULL,
    keyword     VARCHAR(30) NOT NULL,
    source      VARCHAR(15) NOT NULL,
    note        VARCHAR(200)
);

INSERT INTO cpu_performance_tier (tier_rank, lineup, keyword, source, note) VALUES
(1,  'i3', '13100', 'DOC', '기획서 6.2 i3 계열'),
(2,  'i3', '14100', 'DOC', '기획서 6.2 i3 계열'),
(3,  'i5', '13400', 'DOC', '기획서 6.2 i5 계열'),
(3,  'i5', '14400', 'DOC', '기획서 6.2 i5 계열 (13400과 동급)'),
(4,  'i5', '13500', 'DOC', '기획서 6.2 i5 계열'),
(4,  'i5', '14500', 'DOC', '기획서 6.2 i5 계열 (13500과 동급)'),
(5,  'i5', '13600',  'EXTRAPOLATED', '기획서 표에 없는 K없는 13600 - 13500/14500 위, 13600K 아래로 추정. 팀 확인 필요'),
(6,  'i5', '225',   'EXTRAPOLATED', '울트라5 시리즈2 225(+F/T) - 문서표 245K보다 하위로 추정'),
(7,  'i5', '235',   'EXTRAPOLATED', '울트라5 시리즈2 235(+T)'),
(8,  'i5', '245',   'EXTRAPOLATED', '울트라5 시리즈2 245 (비K)'),
(9,  'i5', '245K',  'DOC', '기획서 6.2 명시: 13500/14500 위, 13600K/14600K 아래'),
(10, 'i5', '250K',  'EXTRAPOLATED', '울트라5 250K/KF Plus - 245K보다 상위 추정 (Plus 유무 무관하게 매칭)'),
(11, 'i5', '13600K', 'DOC', '기획서 6.2 i5 계열'),
(11, 'i5', '14600K', 'DOC', '기획서 6.2 i5 계열 (13600K와 동급)'),
(12, 'i7', '13700',  'DOC', '기획서 6.2 i7 계열'),
(13, 'i7', '265',    'EXTRAPOLATED', '울트라7 시리즈2 265(+F/T) 비K'),
(14, 'i7', '265K',   'DOC', '기획서 6.2 명시: 13700 위, 14700 아래'),
(15, 'i7', '270K',   'EXTRAPOLATED', '울트라7 270K/KF Plus - 265K보다 상위 추정'),
(16, 'i7', '14700',  'DOC', '기획서 6.2 i7 계열'),
(17, 'i7', '13700K', 'DOC', '기획서 6.2 i7 계열'),
(18, 'i7', '14700K', 'DOC', '기획서 6.2 i7 계열'),
(19, 'i9', '13900',  'DOC', '기획서 6.2 i9 계열'),
(20, 'i9', '285',    'EXTRAPOLATED', '울트라9 시리즈2 285(+T) 비K'),
(21, 'i9', '285K',   'DOC', '기획서 6.2 명시: 13900 위, 14900 아래'),
(22, 'i9', '14900',  'DOC', '기획서 6.2 i9 계열'),
(23, 'i9', '13900K', 'DOC', '기획서 6.2 i9 계열'),
(24, 'i9', '14900K', 'DOC', '기획서 6.2 i9 계열'),
(25, 'i9', '14900KS','DOC', '기획서 6.2 i9 계열 최상위');

-- tier_rank 재계산 (긴 keyword부터 우선 매칭)
UPDATE cpu_products SET tier_rank = NULL;

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

SELECT 'cpu tier_rank 채워진 개수' AS info, COUNT(*) AS cnt FROM cpu_products WHERE tier_rank IS NOT NULL;
SELECT 'cpu tier_rank 매칭 안 된 상품' AS info, COUNT(*) AS cnt FROM cpu_products WHERE tier_rank IS NULL;
SELECT product_id, name FROM cpu_products WHERE tier_rank IS NULL;

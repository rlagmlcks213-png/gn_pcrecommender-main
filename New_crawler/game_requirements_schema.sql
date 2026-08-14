-- ============================================================
-- 게임 요구사양 테이블 (SFR-001 / DAR-001)
-- - CPU/GPU는 cpu_performance_tier / gpu_performance_tier의 tier_rank를 그대로 참조
--   (숫자 비교만으로 "이 게임을 실행하려면 최소 몇 등급 이상"을 판단 가능)
-- - *_display 컬럼은 실제 DB 매칭용이 아니라 화면에 보여줄 원문 표기(예: "i5-13400")
-- - 이 시스템은 "권장 사양"만 기준으로 삼는다 (최소 사양은 사용하지 않음)
-- - 게임 2개 이상 선택 시 "항목별 최댓값 채택" 규칙은 애플리케이션 로직에서
--   SELECT MAX(cpu_tier_rank), MAX(gpu_tier_rank), MAX(ram_gb), MAX(storage_gb)
--   FROM game_requirements WHERE game_name IN (...) 형태로 그대로 구현 가능하도록 설계함
-- ============================================================
USE DW_db;

DROP TABLE IF EXISTS game_requirements;
CREATE TABLE game_requirements (
    id                  INT AUTO_INCREMENT PRIMARY KEY,
    game_name           VARCHAR(100) NOT NULL UNIQUE,

    -- 권장 사양 (이 시스템의 기준 사양 - 최소사양은 사용하지 않음)
    cpu_tier_rank       INT NULL,          -- cpu_performance_tier.tier_rank 참조
    cpu_display         VARCHAR(50) NULL,  -- 원문 표기, 예: "i7-13700"
    gpu_tier_rank       INT NULL,          -- gpu_performance_tier.tier_rank 참조
    gpu_display         VARCHAR(50) NULL,  -- 예: "RTX 4070"
    ram_gb              SMALLINT UNSIGNED NULL,
    storage_gb          SMALLINT UNSIGNED NULL,

    source_url          VARCHAR(300) NULL,  -- 공식 요구사양 출처(스팀 페이지 등) - 갱신시 검증용
    updated_at          DATE NULL,          -- 원문 확인/입력한 날짜 (DAR-004: 60일마다 갱신 대상)

    INDEX idx_cpu (cpu_tier_rank),
    INDEX idx_gpu (gpu_tier_rank)
);

-- ---------- 참고용 예시 1건 (실제 값은 확정 후 채워야 함) ----------
-- INSERT INTO game_requirements
--   (game_name, cpu_tier_rank, cpu_display, gpu_tier_rank, gpu_display, ram_gb, storage_gb,
--    source_url, updated_at)
-- VALUES
--   ('예시게임', 12, 'i7-13700', 6, 'RTX 4070', 32, 70,
--    'https://store.steampowered.com/app/000000', '2026-08-07');

SELECT '테이블 생성 완료 (권장사양 단일 기준). 게임 목록/실제 사양 입력은 별도 진행' AS info;

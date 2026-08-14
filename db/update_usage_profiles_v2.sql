-- ============================================================
-- 실사용자 제공 "PC 용도별 견적 가이드" 반영.
-- 1) required_ssd_gb/required_hdd_gb 컬럼을 새로 추가한다(이전엔 용도별
--    저장장치 요구량을 전혀 관리하지 않고 "게임 선택 여부"로만 대충
--    1TB/500GB를 나눴는데, 이 가이드로 정확한 근거가 생겼다).
-- 2) 5개 용도의 CPU/GPU/RAM 등급을 가이드 그대로 재조정한다(등급 매핑은
--    cpu_performance_tier_fix.sql/performance_tier.sql 기준 1~25/1~14 스케일).
--
-- 매핑 근거:
--   문서작업: "i5 비K/Ultra5 하위" -> 첫 i5비K(13400)=tier 3, GPU 없음(최저 1)
--   영상편집: "i5-K/i7, Ultra5/7" -> 첫 K모델(Ultra5 245K)=tier 9,
--             GPU "RTX5060Ti~5070"의 하한(5060Ti)=tier 5
--   3D렌더링: "i7/i9, Ultra7/9" -> 첫 i7(13700)=tier 12,
--             GPU "RTX5070Ti~5080/5090"의 하한(5070Ti)=tier 10
--   스트리밍: "i5-K이상/i7,Ultra7" -> tier 9, GPU "RTX5060Ti/5070이상" 하한=tier 5
--   개발/AI:  "i5-K/i7,Ultra5/7" -> tier 9, GPU는 일반 개발 기준 최저(1)
--             — AI/딥러닝 세부용도(VRAM16GB+, GPU tier 9+)는 지금 시스템에
--             "개발" 프로필 하나뿐이라 구분이 안 된다(알려드려야 할 한계).
-- ============================================================
USE DW_db;

ALTER TABLE usage_profiles ADD COLUMN required_ssd_gb SMALLINT UNSIGNED NULL;
ALTER TABLE usage_profiles ADD COLUMN required_hdd_gb SMALLINT UNSIGNED NULL DEFAULT 0;

UPDATE usage_profiles SET required_cpu_tier=3,  required_gpu_tier=1,  required_ram_gb=16, required_ssd_gb=512,  required_hdd_gb=0    WHERE code='OFFICE';
UPDATE usage_profiles SET required_cpu_tier=9,  required_gpu_tier=5,  required_ram_gb=32, required_ssd_gb=1000, required_hdd_gb=2000 WHERE code='VIDEO_EDITING';
UPDATE usage_profiles SET required_cpu_tier=12, required_gpu_tier=10, required_ram_gb=64, required_ssd_gb=2000, required_hdd_gb=4000 WHERE code='RENDERING_3D';
UPDATE usage_profiles SET required_cpu_tier=9,  required_gpu_tier=5,  required_ram_gb=32, required_ssd_gb=1000, required_hdd_gb=0    WHERE code='STREAMING';
UPDATE usage_profiles SET required_cpu_tier=9,  required_gpu_tier=1,  required_ram_gb=32, required_ssd_gb=1000, required_hdd_gb=0    WHERE code='DEVELOPMENT';

SELECT * FROM usage_profiles;

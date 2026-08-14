-- ============================================================
-- usage_profiles의 등급값을 실제 tier_rank 스케일로 재조정.
-- (cpu_performance_tier_fix.sql 기준 CPU 1~25, performance_tier.sql 기준 GPU 1~14)
-- add_missing_tables.sql로 usage_profiles를 이미 만드셨다는 전제.
-- ============================================================
USE DW_db;

UPDATE usage_profiles SET required_cpu_tier = 1,  required_gpu_tier = 1 WHERE code = 'OFFICE';
UPDATE usage_profiles SET required_cpu_tier = 12, required_gpu_tier = 6 WHERE code = 'VIDEO_EDITING';
UPDATE usage_profiles SET required_cpu_tier = 17, required_gpu_tier = 9 WHERE code = 'RENDERING_3D';
UPDATE usage_profiles SET required_cpu_tier = 12, required_gpu_tier = 4 WHERE code = 'STREAMING';
UPDATE usage_profiles SET required_cpu_tier = 8,  required_gpu_tier = 1 WHERE code = 'DEVELOPMENT';

SELECT * FROM usage_profiles;

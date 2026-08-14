-- ============================================================
-- 부품 호환성 체크를 위해 필요한 컬럼들을 미리 추가.
-- danawa_only_load.sql 실행 직후, spec_scraper.py로 스펙을 긁기 전에 한 번 실행.
-- (이미 있는 컬럼은 건드리지 않음 - has_igpu, power_min_w/max_w, ram_slot_count 등)
-- ============================================================
USE DW_db;

-- CPU: 소켓
ALTER TABLE cpu_products
    ADD COLUMN socket VARCHAR(30) NULL;

-- MBoard: 소켓, 폼팩터, RAM 규격
ALTER TABLE mboard_products
    ADD COLUMN socket VARCHAR(30) NULL,
    ADD COLUMN form_factor VARCHAR(20) NULL,   -- ATX / M-ATX / ITX 등
    ADD COLUMN ram_type VARCHAR(10) NULL;      -- DDR4 / DDR5

-- RAM: 규격
ALTER TABLE ram_products
    ADD COLUMN ram_type VARCHAR(10) NULL;      -- DDR4 / DDR5

-- Cooler: 지원 소켓(여러 개 가능하므로 콤마 구분 문자열), 높이
ALTER TABLE cooler_products
    ADD COLUMN support_sockets VARCHAR(300) NULL,  -- 예: "LGA1700,AM5,AM4"
    ADD COLUMN height_mm SMALLINT UNSIGNED NULL,
    ADD COLUMN cooler_type VARCHAR(20) NULL;        -- 공랭 / 수랭 구분 (선택)

-- Case: 지원 폼팩터, 최대 쿨러 높이, 최대 VGA 길이, 지원 파워 폼팩터
ALTER TABLE case_products
    ADD COLUMN support_form_factors VARCHAR(100) NULL,  -- 예: "ATX,M-ATX,ITX"
    ADD COLUMN max_cooler_height_mm SMALLINT UNSIGNED NULL,
    ADD COLUMN max_vga_length_mm SMALLINT UNSIGNED NULL,
    ADD COLUMN support_psu_form_factors VARCHAR(50) NULL; -- 예: "ATX,SFX"

-- VGA: 길이, 요구 전력(권장 파워), 보조전원 커넥터
ALTER TABLE vga_products
    ADD COLUMN length_mm SMALLINT UNSIGNED NULL,
    ADD COLUMN recommended_psu_w SMALLINT UNSIGNED NULL,
    ADD COLUMN power_connector VARCHAR(50) NULL;   -- 예: "8핀 x1"

-- Power: 정격출력, 폼팩터
ALTER TABLE power_products
    ADD COLUMN rated_w SMALLINT UNSIGNED NULL,
    ADD COLUMN form_factor VARCHAR(20) NULL;        -- ATX / SFX / SFX-L 등

SELECT 'ALTER 완료. 이제 각 카테고리에 대해 spec_scraper.py 를 실행해서'
       ' danawa_spec_summary 를 채운 뒤, 아래 discovery_spec_keys.sql 로'
       ' 실제 spec_key/spec_value 형태를 먼저 확인하세요.' AS next_step;

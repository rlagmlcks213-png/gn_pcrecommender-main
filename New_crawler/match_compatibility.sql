-- ============================================================
-- 전체 부품 호환성 매칭 (다나와 데이터만 사용, buildcores 등 외부 DB 미사용)
--
-- 전제조건: add_compat_columns.sql +
--           cpu_socket_update.sql, mboard_socket_formfactor_update.sql,
--           ram_type_update.sql, cooler_spec_update.sql,
--           case_spec_update.sql, vga_spec_update.sql, power_spec_update.sql
--           전부 실행 완료.
--
-- 방식: match_vga.py와 동일한 발상 - "궁합이 맞는 쌍만" 결과 테이블에 저장.
--       카테고리 x 카테고리 전체를 다 저장하면 테이블이 지나치게 커지므로
--       compatible = TRUE 인 쌍만 남깁니다 (호환 안 되는 조합은 그냥 없는 것으로 처리).
-- ============================================================
USE DW_db;

-- ---------- 1) CPU <-> MBoard : 소켓 일치 ----------
DROP TABLE IF EXISTS compat_cpu_mboard;
CREATE TABLE compat_cpu_mboard (
    cpu_id BIGINT UNSIGNED,
    mboard_id BIGINT UNSIGNED,
    socket VARCHAR(30),
    PRIMARY KEY (cpu_id, mboard_id)
);
INSERT INTO compat_cpu_mboard (cpu_id, mboard_id, socket)
SELECT c.product_id, m.product_id, c.socket
FROM cpu_products c
JOIN mboard_products m ON m.socket = c.socket
WHERE c.socket IS NOT NULL AND m.socket IS NOT NULL;

SELECT 'compat_cpu_mboard' AS info, COUNT(*) AS cnt FROM compat_cpu_mboard;

-- ---------- 2) MBoard <-> RAM : 규격(DDR4/DDR5) 일치 ----------
DROP TABLE IF EXISTS compat_mboard_ram;
CREATE TABLE compat_mboard_ram (
    mboard_id BIGINT UNSIGNED,
    ram_id BIGINT UNSIGNED,
    ram_type VARCHAR(10),
    PRIMARY KEY (mboard_id, ram_id)
);
INSERT INTO compat_mboard_ram (mboard_id, ram_id, ram_type)
SELECT m.product_id, r.product_id, m.ram_type
FROM mboard_products m
JOIN ram_products r ON r.ram_type = m.ram_type
WHERE m.ram_type IS NOT NULL AND r.ram_type IS NOT NULL;

SELECT 'compat_mboard_ram' AS info, COUNT(*) AS cnt FROM compat_mboard_ram;

-- ---------- 3) MBoard <-> Case : 폼팩터 호환 ----------
-- 케이스의 지원폼팩터 문자열(예: "ATX, M-ATX") 안에 메인보드 폼팩터가 포함되어 있으면 호환.
-- 큰 보드는 작은 케이스에 안 들어가지만, 작은 보드는 큰 케이스에 대개 들어가므로
-- "케이스 지원목록에 보드 폼팩터가 있는가"로 판단.
DROP TABLE IF EXISTS compat_mboard_case;
CREATE TABLE compat_mboard_case (
    mboard_id BIGINT UNSIGNED,
    case_id BIGINT UNSIGNED,
    mboard_form_factor VARCHAR(20),
    PRIMARY KEY (mboard_id, case_id)
);
INSERT INTO compat_mboard_case (mboard_id, case_id, mboard_form_factor)
SELECT m.product_id, c.product_id, m.form_factor
FROM mboard_products m
JOIN case_products c
  ON c.support_form_factors IS NOT NULL
  AND FIND_IN_SET(m.form_factor, REPLACE(c.support_form_factors, ', ', ',')) > 0
WHERE m.form_factor IS NOT NULL;

SELECT 'compat_mboard_case' AS info, COUNT(*) AS cnt FROM compat_mboard_case;

-- ---------- 4) Cooler <-> CPU : 소켓 지원 여부 ----------
DROP TABLE IF EXISTS compat_cooler_cpu;
CREATE TABLE compat_cooler_cpu (
    cooler_id BIGINT UNSIGNED,
    cpu_id BIGINT UNSIGNED,
    socket VARCHAR(30),
    PRIMARY KEY (cooler_id, cpu_id)
);
INSERT INTO compat_cooler_cpu (cooler_id, cpu_id, socket)
SELECT co.product_id, c.product_id, c.socket
FROM cooler_products co
JOIN cpu_products c
  ON co.support_sockets IS NOT NULL
  AND c.socket IS NOT NULL
  AND FIND_IN_SET(c.socket, REPLACE(co.support_sockets, ', ', ',')) > 0;

SELECT 'compat_cooler_cpu' AS info, COUNT(*) AS cnt FROM compat_cooler_cpu;

-- ---------- 5) Cooler <-> Case : 쿨러 높이 <= 케이스 최대 쿨러 장착 높이 ----------
-- 일체형 수랭 등 height_mm이 없는 쿨러는 이 체크에서 제외 (공랭 쿨러만 대상).
DROP TABLE IF EXISTS compat_cooler_case;
CREATE TABLE compat_cooler_case (
    cooler_id BIGINT UNSIGNED,
    case_id BIGINT UNSIGNED,
    cooler_height_mm SMALLINT UNSIGNED,
    case_max_height_mm SMALLINT UNSIGNED,
    PRIMARY KEY (cooler_id, case_id)
);
INSERT INTO compat_cooler_case (cooler_id, case_id, cooler_height_mm, case_max_height_mm)
SELECT co.product_id, ca.product_id, co.height_mm, ca.max_cooler_height_mm
FROM cooler_products co
JOIN case_products ca
  ON co.height_mm IS NOT NULL
  AND ca.max_cooler_height_mm IS NOT NULL
  AND co.height_mm <= ca.max_cooler_height_mm;

SELECT 'compat_cooler_case' AS info, COUNT(*) AS cnt FROM compat_cooler_case;

-- ---------- 6) VGA <-> Case : VGA 길이 <= 케이스 최대 VGA 장착 길이 ----------
DROP TABLE IF EXISTS compat_vga_case;
CREATE TABLE compat_vga_case (
    vga_id BIGINT UNSIGNED,
    case_id BIGINT UNSIGNED,
    vga_length_mm SMALLINT UNSIGNED,
    case_max_length_mm SMALLINT UNSIGNED,
    PRIMARY KEY (vga_id, case_id)
);
INSERT INTO compat_vga_case (vga_id, case_id, vga_length_mm, case_max_length_mm)
SELECT v.product_id, ca.product_id, v.length_mm, ca.max_vga_length_mm
FROM vga_products v
JOIN case_products ca
  ON v.length_mm IS NOT NULL
  AND ca.max_vga_length_mm IS NOT NULL
  AND v.length_mm <= ca.max_vga_length_mm;

SELECT 'compat_vga_case' AS info, COUNT(*) AS cnt FROM compat_vga_case;

-- ---------- 7) Power <-> Case : 파워 폼팩터 호환 ----------
-- 케이스의 지원파워규격 문자열(예: "표준-ATX", "M-ATX(SFX)") 안에 파워의 폼팩터 키워드가 포함되면 호환.
DROP TABLE IF EXISTS compat_power_case;
CREATE TABLE compat_power_case (
    power_id BIGINT UNSIGNED,
    case_id BIGINT UNSIGNED,
    power_form_factor VARCHAR(20),
    PRIMARY KEY (power_id, case_id)
);
INSERT INTO compat_power_case (power_id, case_id, power_form_factor)
SELECT p.product_id, c.product_id, p.form_factor
FROM power_products p
JOIN case_products c
  ON c.support_psu_form_factors IS NOT NULL
  AND p.form_factor IS NOT NULL
  AND (
        (p.form_factor = 'ATX'  AND c.support_psu_form_factors LIKE '%ATX%' AND c.support_psu_form_factors NOT LIKE '%SFX%')
     OR (p.form_factor = 'SFX'  AND c.support_psu_form_factors LIKE '%SFX%')
     OR (p.form_factor = 'TFX'  AND c.support_psu_form_factors LIKE '%TFX%')
     OR (p.form_factor = 'FLEX' AND c.support_psu_form_factors LIKE '%FLEX%')
  );

SELECT 'compat_power_case' AS info, COUNT(*) AS cnt FROM compat_power_case;

-- ---------- 8) Power 용량 충분 여부 : 특정 CPU+VGA 조합에 맞는 파워 찾기 ----------
-- 이건 상품 쌍이 아니라 "빌드(조합)" 단위 체크라 정적 테이블로 두면 조합 폭발이 나므로,
-- 실제 사용 시 아래처럼 특정 cpu_id / vga_id를 넣어서 그때그때 조회하는 뷰로 둡니다.
-- 예시: CPU 소비전력(power_max_w) + VGA 권장 파워(recommended_psu_w) 중 더 큰 값 이상인 파워만 추천.
DROP VIEW IF EXISTS v_power_recommendation;
CREATE VIEW v_power_recommendation AS
SELECT
    c.product_id AS cpu_id,
    v.product_id AS vga_id,
    GREATEST(COALESCE(c.power_max_w, 0), COALESCE(v.recommended_psu_w, 0)) AS min_required_w
FROM cpu_products c
JOIN vga_products v;
-- 사용 예:
-- SELECT p.product_id, p.name, p.rated_w
-- FROM power_products p
-- JOIN v_power_recommendation req
--   ON req.cpu_id = 1234567 AND req.vga_id = 7654321
-- WHERE p.rated_w >= req.min_required_w
-- ORDER BY p.rated_w ASC
-- LIMIT 10;

SELECT '완료. compat_* 테이블 7개 + v_power_recommendation 뷰 생성됨' AS info;

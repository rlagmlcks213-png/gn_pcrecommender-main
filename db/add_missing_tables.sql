-- ============================================================
-- 부족한 테이블만 추가하는 스크립트 (실제 크롤링 데이터를 건드리지 않음)
--
-- New_crawler 스크립트들은 cpu_products/vga_products/game_requirements 등은
-- 만들지만, usage_profiles(PC 용도)와 product_media(사진/링크)는 이 프로토타입
-- 전용이라 안 만듭니다 — 그래서 API 서버가 "테이블이 없다" 에러를 냅니다.
--
-- IF NOT EXISTS를 써서 이미 있으면 건드리지 않고, cpu_products/vga_products/
-- game_requirements 등 실제 데이터가 든 테이블은 아예 손대지 않습니다.
-- ============================================================
USE DW_db;

CREATE TABLE IF NOT EXISTS usage_profiles (
    id                  INT PRIMARY KEY,
    code                VARCHAR(30) NOT NULL,
    display_name        VARCHAR(50) NOT NULL,
    required_cpu_tier   TINYINT,
    required_gpu_tier   TINYINT,
    required_ram_gb     SMALLINT,
    required_ram_type   VARCHAR(10) NULL
);

INSERT IGNORE INTO usage_profiles (id, code, display_name, required_cpu_tier, required_gpu_tier, required_ram_gb, required_ram_type) VALUES
(1, 'OFFICE', '문서작업/인터넷', 0, 0, 8, NULL),
(2, 'VIDEO_EDITING', '영상편집', 5, 5, 32, 'DDR5'),
(3, 'RENDERING_3D', '3D 렌더링/모델링', 7, 8, 32, 'DDR5'),
(4, 'STREAMING', '방송/스트리밍', 5, 3, 32, NULL),
(5, 'DEVELOPMENT', '개발/컴파일', 4, 0, 32, NULL);

CREATE TABLE IF NOT EXISTS product_media (
    category    VARCHAR(20) NOT NULL,
    product_id  BIGINT UNSIGNED NOT NULL,
    image_url   TEXT NULL,
    product_url VARCHAR(300) NULL,
    PRIMARY KEY (category, product_id)
);

SELECT '완료 — usage_profiles/product_media 준비됨(기존 실제 데이터는 그대로)' AS info;

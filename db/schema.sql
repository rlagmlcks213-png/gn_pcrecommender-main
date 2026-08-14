-- ============================================================
-- 개인 PC 사양 추천 시스템 — DB 스키마 (MySQL)
-- 출처: https://github.com/neungjichai/Danawa-DB (New_crawler/danawa_only_load.sql
--       의 최종 products 테이블 + add_compat_columns.sql)를 그대로 가져왔다.
--
-- *** 원본과 다른 점 ***
-- 1) staging/unpivot/date_map 등 CSV 적재 중간 테이블은 뺐다 — 원본은
--    crawl_data/*.csv를 LOAD DATA INFILE로 읽는데, 이 CSV는 실제 크롤링
--    결과물이라 이 프로젝트엔 없다. 최종 products/prices 테이블 구조만
--    그대로 가져오고, 목업 데이터를 여기 바로 INSERT한다.
-- 2) 저장소에 없는 컬럼을 일부 추가했다(아래 "★ 저장소에 없어서 추가" 표시) —
--    원본 add_compat_columns.sql은 쿨러 냉각 용량(TDP 감당치), 라디에이터
--    크기, RAM/SSD/HDD 용량 컬럼이 없어서 수랭 매칭·용량 기반 검색이
--    불가능했다. 기획서 5.1절 조건을 실제로 계산하려면 필요해서 추가했다.
-- ============================================================

CREATE DATABASE IF NOT EXISTS DW_db CHARACTER SET utf8mb4;
USE DW_db;

-- ---------------- CPU ----------------
DROP TABLE IF EXISTS cpu_products;
CREATE TABLE cpu_products (
    product_id   BIGINT UNSIGNED PRIMARY KEY,
    name         VARCHAR(500),
    company      VARCHAR(50),
    usage_type   VARCHAR(20),
    has_igpu     VARCHAR(10)  NULL,
    power_min_w  SMALLINT UNSIGNED NULL,
    power_max_w  SMALLINT UNSIGNED NULL,
    socket       VARCHAR(30)  NULL          -- add_compat_columns.sql
);

DROP TABLE IF EXISTS cpu_prices;
CREATE TABLE cpu_prices (
    id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id  BIGINT UNSIGNED,
    crawl_date  DATETIME,
    option_name VARCHAR(300),
    price       INT UNSIGNED,
    KEY idx_product_date (product_id, crawl_date)
);

-- ---------------- VGA ----------------
DROP TABLE IF EXISTS vga_products;
CREATE TABLE vga_products (
    product_id        BIGINT UNSIGNED PRIMARY KEY,
    name              VARCHAR(500),
    company           VARCHAR(50),
    usage_type        VARCHAR(20),
    length_mm         SMALLINT UNSIGNED NULL,   -- add_compat_columns.sql
    recommended_psu_w SMALLINT UNSIGNED NULL,   -- add_compat_columns.sql
    power_connector   VARCHAR(50) NULL          -- add_compat_columns.sql
);

DROP TABLE IF EXISTS vga_prices;
CREATE TABLE vga_prices (
    id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id  BIGINT UNSIGNED,
    crawl_date  DATETIME,
    option_name VARCHAR(300),
    price       INT UNSIGNED,
    KEY idx_product_date (product_id, crawl_date)
);

-- ---------------- 메인보드 ----------------
DROP TABLE IF EXISTS mboard_products;
CREATE TABLE mboard_products (
    product_id      BIGINT UNSIGNED PRIMARY KEY,
    name            VARCHAR(500),
    company         VARCHAR(50),
    usage_type      VARCHAR(20),
    ram_slot_count  TINYINT UNSIGNED NULL,
    socket          VARCHAR(30) NULL,           -- add_compat_columns.sql
    form_factor     VARCHAR(20) NULL,           -- add_compat_columns.sql
    ram_type        VARCHAR(10) NULL            -- add_compat_columns.sql
);

DROP TABLE IF EXISTS mboard_prices;
CREATE TABLE mboard_prices (
    id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id  BIGINT UNSIGNED,
    crawl_date  DATETIME,
    option_name VARCHAR(300),
    price       INT UNSIGNED,
    KEY idx_product_date (product_id, crawl_date)
);

-- ---------------- RAM ----------------
DROP TABLE IF EXISTS ram_products;
CREATE TABLE ram_products (
    product_id   BIGINT UNSIGNED PRIMARY KEY,
    name         VARCHAR(500),
    company      VARCHAR(50),
    usage_type   VARCHAR(20),
    ram_type     VARCHAR(10) NULL,              -- add_compat_columns.sql
    capacity_gb  SMALLINT UNSIGNED NULL,         -- ★ 저장소에 없어서 추가(용량 검색에 필수)
    speed_mhz    SMALLINT UNSIGNED NULL          -- ★ 저장소에 없어서 추가
);

DROP TABLE IF EXISTS ram_prices;
CREATE TABLE ram_prices (
    id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id  BIGINT UNSIGNED,
    crawl_date  DATETIME,
    option_name VARCHAR(300),
    price       INT UNSIGNED,
    KEY idx_product_date (product_id, crawl_date)
);

-- ---------------- SSD ----------------
DROP TABLE IF EXISTS ssd_products;
CREATE TABLE ssd_products (
    product_id   BIGINT UNSIGNED PRIMARY KEY,
    name         VARCHAR(500),
    company      VARCHAR(50),
    usage_type   VARCHAR(20),
    capacity_gb  SMALLINT UNSIGNED NULL,         -- ★ 저장소에 없어서 추가
    interface    VARCHAR(30) NULL                -- ★ 저장소에 없어서 추가
);

DROP TABLE IF EXISTS ssd_prices;
CREATE TABLE ssd_prices (
    id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id  BIGINT UNSIGNED,
    crawl_date  DATETIME,
    option_name VARCHAR(300),
    price       INT UNSIGNED,
    KEY idx_product_date (product_id, crawl_date)
);

-- ---------------- HDD ----------------
DROP TABLE IF EXISTS hdd_products;
CREATE TABLE hdd_products (
    product_id   BIGINT UNSIGNED PRIMARY KEY,
    name         VARCHAR(500),
    company      VARCHAR(50),
    usage_type   VARCHAR(20),
    capacity_gb  SMALLINT UNSIGNED NULL          -- ★ 저장소에 없어서 추가
);

DROP TABLE IF EXISTS hdd_prices;
CREATE TABLE hdd_prices (
    id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id  BIGINT UNSIGNED,
    crawl_date  DATETIME,
    option_name VARCHAR(300),
    price       INT UNSIGNED,
    KEY idx_product_date (product_id, crawl_date)
);

-- ---------------- 쿨러 ----------------
DROP TABLE IF EXISTS cooler_products;
CREATE TABLE cooler_products (
    product_id       BIGINT UNSIGNED PRIMARY KEY,
    name             VARCHAR(500),
    company          VARCHAR(50),
    usage_type       VARCHAR(20),
    support_sockets  VARCHAR(300) NULL,          -- add_compat_columns.sql
    height_mm        SMALLINT UNSIGNED NULL,     -- add_compat_columns.sql
    cooler_type      VARCHAR(20) NULL,           -- add_compat_columns.sql
    radiator_mm      SMALLINT UNSIGNED NULL,     -- ★ 저장소에 없어서 추가(수랭 매칭에 필수)
    max_tdp_w        SMALLINT UNSIGNED NULL      -- ★ 저장소에 없어서 추가(CPU 발열 감당 검증에 필수)
);

DROP TABLE IF EXISTS cooler_prices;
CREATE TABLE cooler_prices (
    id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id  BIGINT UNSIGNED,
    crawl_date  DATETIME,
    option_name VARCHAR(300),
    price       INT UNSIGNED,
    KEY idx_product_date (product_id, crawl_date)
);

-- ---------------- 파워(PSU) ----------------
DROP TABLE IF EXISTS power_products;
CREATE TABLE power_products (
    product_id   BIGINT UNSIGNED PRIMARY KEY,
    name         VARCHAR(500),
    company      VARCHAR(50),
    usage_type   VARCHAR(20),
    rated_w      SMALLINT UNSIGNED NULL,         -- add_compat_columns.sql
    form_factor  VARCHAR(20) NULL                -- add_compat_columns.sql
);

DROP TABLE IF EXISTS power_prices;
CREATE TABLE power_prices (
    id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id  BIGINT UNSIGNED,
    crawl_date  DATETIME,
    option_name VARCHAR(300),
    price       INT UNSIGNED,
    KEY idx_product_date (product_id, crawl_date)
);

-- ---------------- 케이스 ----------------
DROP TABLE IF EXISTS case_products;
CREATE TABLE case_products (
    product_id               BIGINT UNSIGNED PRIMARY KEY,
    name                     VARCHAR(500),
    company                  VARCHAR(50),
    usage_type               VARCHAR(20),
    support_form_factors     VARCHAR(100) NULL,  -- add_compat_columns.sql
    max_cooler_height_mm     SMALLINT UNSIGNED NULL,  -- add_compat_columns.sql
    max_vga_length_mm        SMALLINT UNSIGNED NULL,  -- add_compat_columns.sql
    support_psu_form_factors VARCHAR(50) NULL,   -- add_compat_columns.sql
    support_radiator_mm      VARCHAR(50) NULL    -- ★ 저장소에 없어서 추가(수랭 매칭에 필수)
);

DROP TABLE IF EXISTS case_prices;
CREATE TABLE case_prices (
    id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id  BIGINT UNSIGNED,
    crawl_date  DATETIME,
    option_name VARCHAR(300),
    price       INT UNSIGNED,
    KEY idx_product_date (product_id, crawl_date)
);

-- ============================================================
-- 최신가 뷰 — 각 상품의 가장 최근 crawl_date 기준 최저가.
-- ============================================================
DROP VIEW IF EXISTS cpu_products_v;
CREATE VIEW cpu_products_v AS
SELECT p.*, latest.price AS price_krw
FROM cpu_products p
JOIN (
    SELECT product_id, MIN(price) AS price
    FROM cpu_prices
    WHERE crawl_date = (SELECT MAX(crawl_date) FROM cpu_prices)
    GROUP BY product_id
) latest ON latest.product_id = p.product_id;

DROP VIEW IF EXISTS vga_products_v;
CREATE VIEW vga_products_v AS
SELECT p.*, latest.price AS price_krw
FROM vga_products p
JOIN (
    SELECT product_id, MIN(price) AS price
    FROM vga_prices
    WHERE crawl_date = (SELECT MAX(crawl_date) FROM vga_prices)
    GROUP BY product_id
) latest ON latest.product_id = p.product_id;

DROP VIEW IF EXISTS mboard_products_v;
CREATE VIEW mboard_products_v AS
SELECT p.*, latest.price AS price_krw
FROM mboard_products p
JOIN (
    SELECT product_id, MIN(price) AS price
    FROM mboard_prices
    WHERE crawl_date = (SELECT MAX(crawl_date) FROM mboard_prices)
    GROUP BY product_id
) latest ON latest.product_id = p.product_id;

DROP VIEW IF EXISTS ram_products_v;
CREATE VIEW ram_products_v AS
SELECT p.*, latest.price AS price_krw
FROM ram_products p
JOIN (
    SELECT product_id, MIN(price) AS price
    FROM ram_prices
    WHERE crawl_date = (SELECT MAX(crawl_date) FROM ram_prices)
    GROUP BY product_id
) latest ON latest.product_id = p.product_id;

DROP VIEW IF EXISTS ssd_products_v;
CREATE VIEW ssd_products_v AS
SELECT p.*, latest.price AS price_krw
FROM ssd_products p
JOIN (
    SELECT product_id, MIN(price) AS price
    FROM ssd_prices
    WHERE crawl_date = (SELECT MAX(crawl_date) FROM ssd_prices)
    GROUP BY product_id
) latest ON latest.product_id = p.product_id;

DROP VIEW IF EXISTS hdd_products_v;
CREATE VIEW hdd_products_v AS
SELECT p.*, latest.price AS price_krw
FROM hdd_products p
JOIN (
    SELECT product_id, MIN(price) AS price
    FROM hdd_prices
    WHERE crawl_date = (SELECT MAX(crawl_date) FROM hdd_prices)
    GROUP BY product_id
) latest ON latest.product_id = p.product_id;

DROP VIEW IF EXISTS cooler_products_v;
CREATE VIEW cooler_products_v AS
SELECT p.*, latest.price AS price_krw
FROM cooler_products p
JOIN (
    SELECT product_id, MIN(price) AS price
    FROM cooler_prices
    WHERE crawl_date = (SELECT MAX(crawl_date) FROM cooler_prices)
    GROUP BY product_id
) latest ON latest.product_id = p.product_id;

DROP VIEW IF EXISTS power_products_v;
CREATE VIEW power_products_v AS
SELECT p.*, latest.price AS price_krw
FROM power_products p
JOIN (
    SELECT product_id, MIN(price) AS price
    FROM power_prices
    WHERE crawl_date = (SELECT MAX(crawl_date) FROM power_prices)
    GROUP BY product_id
) latest ON latest.product_id = p.product_id;

DROP VIEW IF EXISTS case_products_v;
CREATE VIEW case_products_v AS
SELECT p.*, latest.price AS price_krw
FROM case_products p
JOIN (
    SELECT product_id, MIN(price) AS price
    FROM case_prices
    WHERE crawl_date = (SELECT MAX(crawl_date) FROM case_prices)
    GROUP BY product_id
) latest ON latest.product_id = p.product_id;

-- ============================================================
-- 게임/용도 요구사양 (기획서 2.1절 — 저장소엔 없는, 이 프로젝트 자체 테이블)
-- ============================================================
DROP TABLE IF EXISTS game_requirements;
CREATE TABLE game_requirements (
    id                  INT PRIMARY KEY,
    title               VARCHAR(100) NOT NULL,
    required_cpu_tier   TINYINT,
    required_gpu_tier   TINYINT,
    required_ram_gb     SMALLINT,
    required_ram_type   VARCHAR(10) NULL
);

DROP TABLE IF EXISTS usage_profiles;
CREATE TABLE usage_profiles (
    id                  INT PRIMARY KEY,
    code                VARCHAR(30) NOT NULL,
    display_name        VARCHAR(50) NOT NULL,
    required_cpu_tier   TINYINT,
    required_gpu_tier   TINYINT,
    required_ram_gb     SMALLINT,
    required_ram_type   VARCHAR(10) NULL
);

-- ============================================================
-- 부품 사진/링크 (실제 저장소의 spec_scraper.py가 만드는 product_media
-- 테이블과 정확히 같은 구조 — 나중에 실제 덤프가 들어오면 코드 변경 없이
-- 그대로 연결된다. 지금은 목업 플레이스홀더 이미지로 채운다.
-- ============================================================
DROP TABLE IF EXISTS product_media;
CREATE TABLE product_media (
    category    VARCHAR(20) NOT NULL,
    product_id  BIGINT UNSIGNED NOT NULL,
    image_url   TEXT NULL,
    product_url VARCHAR(300) NULL,
    PRIMARY KEY (category, product_id)
);

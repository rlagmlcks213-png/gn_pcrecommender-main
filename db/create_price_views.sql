-- ============================================================
-- 최신가 뷰 — 실제 크롤러 스키마(New_crawler)의 *_prices 테이블
-- (id, product_id, crawl_date, option_name, price) 구조에 맞춰 생성.
-- danawa_only_load.sql 등 실제 데이터 적재가 끝난 뒤 한 번 실행하면 된다.
-- ============================================================
USE DW_db;

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

SELECT '가격 뷰 9개 생성 완료' AS info;

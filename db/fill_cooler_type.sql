-- ============================================================
-- 쿨러 타입(공랭/수랭) 채우기 — cooler_spec_update.sql에 이 로직이 빠져있어서
-- (support_sockets/height_mm만 채우고 cooler_type은 채우지 않음) 별도로 만듦.
--
-- 상품명에 "수랭", "일체형", "AIO", 또는 라디에이터 크기(120/140/240/280/
-- 360/420mm)가 있으면 수랭으로, 나머지는 공랭으로 판단한다.
-- ============================================================
USE DW_db;
SET SQL_SAFE_UPDATES = 0;

UPDATE cooler_products
SET cooler_type = CASE
    WHEN name REGEXP '수랭|일체형|AIO|240|280|360|420'
        THEN '수랭'
    ELSE '공랭'
END
WHERE cooler_type IS NULL;

SELECT cooler_type, COUNT(*) AS cnt FROM cooler_products GROUP BY cooler_type;

-- =============================================================
-- 01 Data quality & warm-up queries
-- =============================================================

-- Q1a. Row count of every table in one result
SELECT 'customers'            AS table_name, COUNT(*) AS row_count FROM customers
UNION ALL SELECT 'sellers',              COUNT(*) FROM sellers
UNION ALL SELECT 'products',             COUNT(*) FROM products
UNION ALL SELECT 'category_translation', COUNT(*) FROM category_translation
UNION ALL SELECT 'geolocation',          COUNT(*) FROM geolocation
UNION ALL SELECT 'orders',               COUNT(*) FROM orders
UNION ALL SELECT 'order_items',          COUNT(*) FROM order_items
UNION ALL SELECT 'order_payments',       COUNT(*) FROM order_payments
UNION ALL SELECT 'order_reviews',        COUNT(*) FROM order_reviews
ORDER BY row_count DESC;


-- Q1b. Date range covered by orders
SELECT
    MIN(order_purchase_timestamp) AS first_order,
    MAX(order_purchase_timestamp) AS last_order
FROM orders;


-- Q2. Orders by status, with % of total
SELECT
    order_status,
    COUNT(*)                                            AS orders,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)  AS pct_of_orders
FROM orders
GROUP BY order_status
ORDER BY orders DESC;


-- Q3. Review score distribution
SELECT
    review_score,
    COUNT(*)                                            AS reviews,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)  AS pct_of_reviews
FROM order_reviews
GROUP BY review_score
ORDER BY review_score;


-- Q4. Top 10 categories (English) by items sold
-- LEFT JOINs keep products with no category / no translation;
-- COALESCE falls back to the Portuguese name, then to 'unknown'.
SELECT
    COALESCE(t.product_category_name_english,
             p.product_category_name,
             'unknown')            AS category,
    COUNT(*)                       AS items_sold
FROM order_items oi
JOIN products p                   ON p.product_id = oi.product_id
LEFT JOIN category_translation t  ON t.product_category_name = p.product_category_name
GROUP BY 1
ORDER BY items_sold DESC
LIMIT 10;

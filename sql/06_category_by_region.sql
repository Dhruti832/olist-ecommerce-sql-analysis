-- =============================================================
-- 06 Business Q5: Category performance by region
-- Region = customer state. Revenue = price + freight_value,
-- delivered orders, Jan 2017 - Aug 2018.
-- =============================================================

-- Q7. Revenue by customer state x category (full grid, feeds Power BI)
SELECT
    c.customer_state,
    COALESCE(t.product_category_name_english,
             p.product_category_name, 'unknown')   AS category,
    COUNT(DISTINCT o.order_id)                      AS orders,
    ROUND(SUM(oi.price + oi.freight_value), 2)      AS revenue
FROM orders o
JOIN customers c                  ON c.customer_id = o.customer_id
JOIN order_items oi               ON oi.order_id = o.order_id
JOIN products p                   ON p.product_id = oi.product_id
LEFT JOIN category_translation t  ON t.product_category_name = p.product_category_name
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp >= '2017-01-01'
  AND o.order_purchase_timestamp <  '2018-09-01'
GROUP BY 1, 2
ORDER BY c.customer_state, revenue DESC;


-- Q7b. Revenue by state (context: how concentrated is demand?)
SELECT
    c.customer_state,
    COUNT(DISTINCT o.order_id)                                   AS orders,
    ROUND(SUM(oi.price + oi.freight_value), 2)                   AS revenue,
    ROUND(100.0 * SUM(oi.price + oi.freight_value)
                / SUM(SUM(oi.price + oi.freight_value)) OVER (), 2) AS pct_of_revenue,
    ROUND(AVG(oi.freight_value), 2)                              AS avg_freight_per_item
FROM orders o
JOIN customers c    ON c.customer_id = o.customer_id
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp >= '2017-01-01'
  AND o.order_purchase_timestamp <  '2018-09-01'
GROUP BY 1
ORDER BY revenue DESC;


-- Q11. Top 3 categories in each state
WITH state_category AS (
    SELECT
        c.customer_state,
        COALESCE(t.product_category_name_english,
                 p.product_category_name, 'unknown')   AS category,
        SUM(oi.price + oi.freight_value)                AS revenue
    FROM orders o
    JOIN customers c                  ON c.customer_id = o.customer_id
    JOIN order_items oi               ON oi.order_id = o.order_id
    JOIN products p                   ON p.product_id = oi.product_id
    LEFT JOIN category_translation t  ON t.product_category_name = p.product_category_name
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp <  '2018-09-01'
    GROUP BY 1, 2
),
ranked AS (
    SELECT
        *,
        DENSE_RANK() OVER (PARTITION BY customer_state ORDER BY revenue DESC) AS category_rank,
        100.0 * revenue / SUM(revenue) OVER (PARTITION BY customer_state)     AS pct_of_state
    FROM state_category
)
SELECT
    customer_state,
    category_rank,
    category,
    ROUND(revenue, 2)       AS revenue,
    ROUND(pct_of_state, 1)  AS pct_of_state_revenue
FROM ranked
WHERE category_rank <= 3
ORDER BY customer_state, category_rank;

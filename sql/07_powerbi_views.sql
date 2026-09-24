-- =============================================================
-- 07 Views for the Power BI dashboard
-- Power BI imports these instead of raw tables, so business logic
-- (revenue definition, date window, delay buckets) lives in SQL.
-- Scope: delivered orders, Jan 2017 - Aug 2018.
-- =============================================================

-- Fact: one row per order. Slicers (date, state) filter this view,
-- and through the order_id relationship, vw_order_items too.
CREATE OR REPLACE VIEW vw_orders AS
WITH items AS (             -- aggregate items first to avoid join fan-out
    SELECT
        order_id,
        COUNT(*)                       AS items,
        SUM(price)                     AS product_value,
        SUM(freight_value)             AS freight_value,
        SUM(price + freight_value)     AS revenue
    FROM order_items
    GROUP BY order_id
),
reviews AS (                -- one score per order
    SELECT order_id, AVG(review_score) AS review_score
    FROM order_reviews
    GROUP BY order_id
)
SELECT
    o.order_id,
    c.customer_unique_id,
    c.customer_state,
    o.order_purchase_timestamp::date                           AS purchase_date,
    DATE_TRUNC('month', o.order_purchase_timestamp)::date      AS order_month,
    i.items,
    ROUND(i.product_value, 2)                                  AS product_value,
    ROUND(i.freight_value, 2)                                  AS freight_value,
    ROUND(i.revenue, 2)                                        AS revenue,
    o.order_delivered_customer_date::date
      - o.order_estimated_delivery_date::date                  AS delay_days,
    CASE
        WHEN o.order_delivered_customer_date IS NULL THEN NULL
        WHEN o.order_delivered_customer_date::date
           < o.order_estimated_delivery_date::date  THEN '1. Early'
        WHEN o.order_delivered_customer_date::date
           = o.order_estimated_delivery_date::date  THEN '2. On time'
        WHEN o.order_delivered_customer_date::date
           - o.order_estimated_delivery_date::date <= 3 THEN '3. 1-3 days late'
        WHEN o.order_delivered_customer_date::date
           - o.order_estimated_delivery_date::date <= 7 THEN '4. 4-7 days late'
        ELSE '5. 8+ days late'
    END                                                        AS delay_bucket,
    ROUND(r.review_score, 2)                                   AS review_score
FROM orders o
JOIN customers c   ON c.customer_id = o.customer_id
JOIN items i       ON i.order_id = o.order_id
LEFT JOIN reviews r ON r.order_id = o.order_id
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp >= '2017-01-01'
  AND o.order_purchase_timestamp <  '2018-09-01';


-- Detail: one row per item line, with category and seller.
CREATE OR REPLACE VIEW vw_order_items AS
SELECT
    oi.order_id,
    oi.order_item_id,
    oi.seller_id,
    s.seller_state,
    COALESCE(t.product_category_name_english,
             p.product_category_name, 'unknown')   AS category,
    oi.price,
    oi.freight_value,
    oi.price + oi.freight_value                     AS revenue
FROM order_items oi
JOIN orders o                     ON o.order_id = oi.order_id
JOIN sellers s                    ON s.seller_id = oi.seller_id
JOIN products p                   ON p.product_id = oi.product_id
LEFT JOIN category_translation t  ON t.product_category_name = p.product_category_name
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp >= '2017-01-01'
  AND o.order_purchase_timestamp <  '2018-09-01';


-- Sellers with >= 30 reviewed orders: revenue vs. rating ranks.
CREATE OR REPLACE VIEW vw_seller_summary AS
WITH seller_orders AS (
    SELECT
        oi.seller_id,
        oi.order_id,
        SUM(oi.price + oi.freight_value) AS revenue
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp <  '2018-09-01'
    GROUP BY oi.seller_id, oi.order_id
),
order_scores AS (
    SELECT order_id, AVG(review_score) AS review_score
    FROM order_reviews
    GROUP BY order_id
),
seller_stats AS (
    SELECT
        so.seller_id,
        COUNT(*)                   AS orders,
        SUM(so.revenue)            AS revenue,
        COUNT(os.review_score)     AS reviewed_orders,
        AVG(os.review_score)       AS avg_rating
    FROM seller_orders so
    LEFT JOIN order_scores os ON os.order_id = so.order_id
    GROUP BY so.seller_id
)
SELECT
    ss.seller_id,
    LEFT(ss.seller_id, 8)                          AS seller_short_id,
    s.seller_state,
    ss.orders,
    ROUND(ss.revenue, 2)                           AS revenue,
    ss.reviewed_orders,
    ROUND(ss.avg_rating, 2)                        AS avg_rating,
    RANK() OVER (ORDER BY ss.revenue DESC)         AS revenue_rank,
    RANK() OVER (ORDER BY ss.avg_rating DESC)      AS rating_rank
FROM seller_stats ss
JOIN sellers s ON s.seller_id = ss.seller_id
WHERE ss.reviewed_orders >= 30;


-- Cohort retention, long format, months 0-12, observable months only.
CREATE OR REPLACE VIEW vw_cohort_retention AS
WITH customer_months AS (
    SELECT DISTINCT
        c.customer_unique_id,
        DATE_TRUNC('month', o.order_purchase_timestamp)::date AS order_month
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
),
cohorts AS (
    SELECT
        customer_unique_id,
        order_month,
        MIN(order_month) OVER (PARTITION BY customer_unique_id) AS cohort_month
    FROM customer_months
),
activity AS (
    SELECT
        cohort_month,
        (EXTRACT(YEAR  FROM AGE(order_month, cohort_month)) * 12
       + EXTRACT(MONTH FROM AGE(order_month, cohort_month)))::int AS month_number,
        COUNT(*) AS active_customers
    FROM cohorts
    GROUP BY 1, 2
),
grid AS (                   -- every observable (cohort, month) pair, so
    SELECT                  -- months with 0 returning customers show 0%
        cm.cohort_month,
        n.month_number
    FROM (SELECT DISTINCT cohort_month FROM activity) cm
    CROSS JOIN generate_series(0, 12) AS n(month_number)
    WHERE cm.cohort_month + n.month_number * INTERVAL '1 month' < '2018-09-01'
)
SELECT
    g.cohort_month,
    g.month_number,
    COALESCE(a.active_customers, 0)                              AS active_customers,
    MAX(a.active_customers) FILTER (WHERE g.month_number = 0)
        OVER (PARTITION BY g.cohort_month)                       AS cohort_size,
    ROUND(100.0 * COALESCE(a.active_customers, 0)
          / MAX(a.active_customers) FILTER (WHERE g.month_number = 0)
              OVER (PARTITION BY g.cohort_month), 2)             AS retention_pct
FROM grid g
LEFT JOIN activity a ON a.cohort_month = g.cohort_month
                    AND a.month_number = g.month_number
WHERE g.cohort_month >= '2017-01-01';

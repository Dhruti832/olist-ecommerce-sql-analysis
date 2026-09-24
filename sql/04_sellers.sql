-- =============================================================
-- 04 Business Q3: Top sellers by revenue and by rating
-- Revenue = price + freight_value, delivered orders, Jan 2017 - Aug 2018.
-- =============================================================

-- Q9a. Top 20 sellers by revenue, with share of total and cumulative share
WITH seller_revenue AS (
    SELECT
        oi.seller_id,
        COUNT(DISTINCT oi.order_id)        AS orders,
        SUM(oi.price + oi.freight_value)   AS revenue
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp <  '2018-09-01'
    GROUP BY oi.seller_id
)
SELECT
    RANK() OVER (ORDER BY revenue DESC)                           AS revenue_rank,
    sr.seller_id,
    s.seller_state,
    sr.orders,
    ROUND(sr.revenue, 2)                                          AS revenue,
    ROUND(100.0 * sr.revenue / SUM(sr.revenue) OVER (), 2)        AS pct_of_revenue,
    ROUND(100.0 * SUM(sr.revenue) OVER (ORDER BY sr.revenue DESC
                                        ROWS UNBOUNDED PRECEDING)
                / SUM(sr.revenue) OVER (), 2)                     AS cumulative_pct
FROM seller_revenue sr
JOIN sellers s ON s.seller_id = sr.seller_id
ORDER BY revenue_rank
LIMIT 20;


-- Q9b. Pareto summary: what share of sellers generates 80% of revenue?
WITH seller_revenue AS (
    SELECT oi.seller_id, SUM(oi.price + oi.freight_value) AS revenue
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp <  '2018-09-01'
    GROUP BY oi.seller_id
),
cumulative AS (
    SELECT
        seller_id,
        SUM(revenue) OVER (ORDER BY revenue DESC ROWS UNBOUNDED PRECEDING)
          / SUM(revenue) OVER ()  AS cumulative_share
    FROM seller_revenue
)
SELECT
    COUNT(*)                                                     AS total_sellers,
    COUNT(*) FILTER (WHERE cumulative_share <= 0.80)             AS sellers_for_80pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE cumulative_share <= 0.80)
                / COUNT(*), 1)                                   AS pct_of_sellers
FROM cumulative;


-- Q10. Sellers by rating (min. 30 reviewed orders) vs. revenue rank
-- A review belongs to an order; if an order has several sellers, each one
-- gets that order's score.
WITH seller_revenue AS (
    SELECT oi.seller_id, SUM(oi.price + oi.freight_value) AS revenue
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp <  '2018-09-01'
    GROUP BY oi.seller_id
),
seller_orders AS (          -- one row per (seller, order), removes item fan-out
    SELECT DISTINCT oi.seller_id, oi.order_id
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp <  '2018-09-01'
),
order_scores AS (           -- one score per order
    SELECT order_id, AVG(review_score) AS review_score
    FROM order_reviews
    GROUP BY order_id
),
seller_rating AS (
    SELECT
        so.seller_id,
        COUNT(*)              AS reviewed_orders,
        AVG(os.review_score)  AS avg_rating
    FROM seller_orders so
    JOIN order_scores os ON os.order_id = so.order_id
    GROUP BY so.seller_id
    HAVING COUNT(*) >= 30
),
ranked AS (
    SELECT
        sr.seller_id,
        ROUND(rv.revenue, 2)                         AS revenue,
        sr.reviewed_orders,
        ROUND(sr.avg_rating, 2)                      AS avg_rating,
        RANK() OVER (ORDER BY rv.revenue DESC)       AS revenue_rank,
        RANK() OVER (ORDER BY sr.avg_rating DESC)    AS rating_rank,
        COUNT(*) OVER ()                             AS qualified_sellers
    FROM seller_rating sr
    JOIN seller_revenue rv ON rv.seller_id = sr.seller_id
)
SELECT *
FROM ranked
WHERE revenue_rank <= 20       -- swap to rating_rank <= 20 for the top-rated list
ORDER BY revenue_rank;

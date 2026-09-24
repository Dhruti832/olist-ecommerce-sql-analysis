-- =============================================================
-- 02 Business Q1: Monthly revenue trend & growth
-- Revenue = price + freight_value from order_items, delivered orders only.
-- Window: Jan 2017 - Aug 2018 (2016 is sparse / has a missing month,
-- Sep-Oct 2018 have no delivered orders).
-- =============================================================

-- Q5. Monthly revenue & order count
SELECT
    DATE_TRUNC('month', o.order_purchase_timestamp)::date  AS month,
    COUNT(DISTINCT o.order_id)                             AS orders,
    ROUND(SUM(oi.price + oi.freight_value), 2)             AS revenue
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp >= '2017-01-01'
  AND o.order_purchase_timestamp <  '2018-09-01'
GROUP BY 1
ORDER BY 1;


-- Q8. Month-over-month growth, 3-month rolling average, year-over-year growth
-- CTE computes monthly revenue once; window functions then look at
-- neighbouring rows (LAG = previous row, ROWS BETWEEN = sliding frame).
WITH monthly AS (
    SELECT
        DATE_TRUNC('month', o.order_purchase_timestamp)::date  AS month,
        COUNT(DISTINCT o.order_id)                             AS orders,
        SUM(oi.price + oi.freight_value)                       AS revenue
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp <  '2018-09-01'
    GROUP BY 1
)
SELECT
    month,
    orders,
    ROUND(revenue, 2)                                              AS revenue,
    ROUND(LAG(revenue) OVER (ORDER BY month), 2)                   AS prev_month_revenue,
    ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY month))
                / LAG(revenue) OVER (ORDER BY month), 1)           AS mom_growth_pct,
    ROUND(AVG(revenue) OVER (ORDER BY month
                             ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2)
                                                                   AS rolling_3m_avg,
    ROUND(100.0 * (revenue - LAG(revenue, 12) OVER (ORDER BY month))
                / LAG(revenue, 12) OVER (ORDER BY month), 1)       AS yoy_growth_pct
FROM monthly
ORDER BY month;

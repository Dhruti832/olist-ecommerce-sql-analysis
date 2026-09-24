-- =============================================================
-- 05 Business Q4: Repeat customers & cohort retention
-- Customer = customer_unique_id (customer_id is per order).
-- Delivered orders only, Jan 2017 - Aug 2018 (cohorts: first purchase
-- in that window).
-- =============================================================

-- Q12. Repeat-customer rate
-- Strict version counts only customers who bought on 2+ different days:
-- several orders on the same day are usually one basket split across
-- sellers, not a return visit.
WITH customer_orders AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id)                          AS orders,
        COUNT(DISTINCT o.order_purchase_timestamp::date)    AS purchase_days
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp <  '2018-09-01'
    GROUP BY c.customer_unique_id
)
SELECT
    COUNT(*)                                                  AS customers,
    COUNT(*) FILTER (WHERE orders >= 2)                       AS repeat_customers,
    ROUND(100.0 * COUNT(*) FILTER (WHERE orders >= 2)
                / COUNT(*), 2)                                AS repeat_rate_pct,
    COUNT(*) FILTER (WHERE purchase_days >= 2)                AS repeat_customers_strict,
    ROUND(100.0 * COUNT(*) FILTER (WHERE purchase_days >= 2)
                / COUNT(*), 2)                                AS repeat_rate_strict_pct,
    ROUND(AVG(orders), 3)                                     AS avg_orders_per_customer
FROM customer_orders;


-- Q13. Monthly cohort retention (long format, suits a Power BI matrix)
-- Cohort = month of first purchase. month_number = months since then.
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
cohort_activity AS (
    SELECT
        cohort_month,
        (EXTRACT(YEAR  FROM AGE(order_month, cohort_month)) * 12
       + EXTRACT(MONTH FROM AGE(order_month, cohort_month)))::int AS month_number,
        COUNT(DISTINCT customer_unique_id)                       AS active_customers
    FROM cohorts
    GROUP BY 1, 2
)
SELECT
    cohort_month,
    month_number,
    active_customers,
    FIRST_VALUE(active_customers) OVER (PARTITION BY cohort_month
                                        ORDER BY month_number)   AS cohort_size,
    ROUND(100.0 * active_customers
          / FIRST_VALUE(active_customers) OVER (PARTITION BY cohort_month
                                                ORDER BY month_number), 2)
                                                                 AS retention_pct
FROM cohort_activity
WHERE cohort_month >= '2017-01-01'
  AND cohort_month <  '2018-09-01'
ORDER BY cohort_month, month_number;


-- Q13b. Cohort retention matrix, months 1-6 as columns (for the README)
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
offsets AS (
    SELECT
        customer_unique_id,
        cohort_month,
        (EXTRACT(YEAR  FROM AGE(order_month, cohort_month)) * 12
       + EXTRACT(MONTH FROM AGE(order_month, cohort_month)))::int AS month_number
    FROM cohorts
),
counts AS (
    SELECT
        cohort_month,
        COUNT(*) FILTER (WHERE month_number = 0) AS m0,
        COUNT(*) FILTER (WHERE month_number = 1) AS m1,
        COUNT(*) FILTER (WHERE month_number = 2) AS m2,
        COUNT(*) FILTER (WHERE month_number = 3) AS m3,
        COUNT(*) FILTER (WHERE month_number = 4) AS m4,
        COUNT(*) FILTER (WHERE month_number = 5) AS m5,
        COUNT(*) FILTER (WHERE month_number = 6) AS m6
    FROM offsets
    WHERE cohort_month >= '2017-01-01'
      AND cohort_month <  '2018-09-01'
    GROUP BY cohort_month
)
-- A month after the data ends (Aug 2018) is not observable yet: show NULL,
-- not 0%, so recent cohorts don't look like they churned.
SELECT
    cohort_month,
    m0 AS cohort_size,
    CASE WHEN cohort_month + INTERVAL '1 month' < '2018-09-01' THEN ROUND(100.0 * m1 / m0, 2) END AS m1,
    CASE WHEN cohort_month + INTERVAL '2 month' < '2018-09-01' THEN ROUND(100.0 * m2 / m0, 2) END AS m2,
    CASE WHEN cohort_month + INTERVAL '3 month' < '2018-09-01' THEN ROUND(100.0 * m3 / m0, 2) END AS m3,
    CASE WHEN cohort_month + INTERVAL '4 month' < '2018-09-01' THEN ROUND(100.0 * m4 / m0, 2) END AS m4,
    CASE WHEN cohort_month + INTERVAL '5 month' < '2018-09-01' THEN ROUND(100.0 * m5 / m0, 2) END AS m5,
    CASE WHEN cohort_month + INTERVAL '6 month' < '2018-09-01' THEN ROUND(100.0 * m6 / m0, 2) END AS m6
FROM counts
ORDER BY cohort_month;


-- Q14. Days between a customer's 1st and 2nd order
WITH customer_orders AS (
    SELECT DISTINCT
        c.customer_unique_id,
        o.order_id,
        o.order_purchase_timestamp
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp <  '2018-09-01'
),
sequenced AS (
    SELECT
        customer_unique_id,
        ROW_NUMBER() OVER (PARTITION BY customer_unique_id
                           ORDER BY order_purchase_timestamp)   AS order_seq,
        order_purchase_timestamp,
        LEAD(order_purchase_timestamp) OVER (PARTITION BY customer_unique_id
                                             ORDER BY order_purchase_timestamp) AS next_order_ts
    FROM customer_orders
),
gaps AS (
    SELECT next_order_ts::date - order_purchase_timestamp::date AS days_to_2nd
    FROM sequenced
    WHERE order_seq = 1
      AND next_order_ts IS NOT NULL
)
SELECT
    COUNT(*)                                                    AS repeat_customers,
    ROUND(AVG(days_to_2nd), 1)                                  AS avg_days,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY days_to_2nd)    AS median_days,
    ROUND(100.0 * AVG((days_to_2nd = 0)::int), 1)               AS pct_same_day,
    ROUND(100.0 * AVG((days_to_2nd <= 30)::int), 1)             AS pct_within_30d
FROM gaps;


-- Q15. Does a late first delivery reduce the chance of a repeat purchase?
-- Two-proportion z-test: z = (p_on_time - p_late) / SE, with pooled SE;
-- two-sided p-value = erfc(|z| / sqrt(2)).
-- Bias check: late deliveries peaked in late 2017 / early 2018 (see Q6c),
-- and customers who first bought near the end of the data had less time to
-- return. The second row keeps only first orders before Mar 2018, so every
-- customer had at least 6 months to come back.
WITH customer_orders AS (
    SELECT
        c.customer_unique_id,
        o.order_purchase_timestamp,
        o.order_delivered_customer_date::date
          > o.order_estimated_delivery_date::date               AS is_late,
        ROW_NUMBER() OVER (PARTITION BY c.customer_unique_id
                           ORDER BY o.order_purchase_timestamp)  AS order_seq,
        COUNT(*)     OVER (PARTITION BY c.customer_unique_id)    AS total_orders
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp <  '2018-09-01'
),
first_orders AS (
    SELECT order_purchase_timestamp, is_late, (total_orders >= 2)::int AS repeated
    FROM customer_orders
    WHERE order_seq = 1
),
samples AS (
    SELECT '1. All first orders' AS sample, is_late, repeated
    FROM first_orders
    UNION ALL
    SELECT '2. First order before Mar 2018', is_late, repeated
    FROM first_orders
    WHERE order_purchase_timestamp < '2018-03-01'
),
rates AS (
    SELECT
        sample,
        COUNT(*)      FILTER (WHERE NOT is_late)  AS n_on_time,
        AVG(repeated) FILTER (WHERE NOT is_late)  AS p_on_time,
        COUNT(*)      FILTER (WHERE is_late)      AS n_late,
        AVG(repeated) FILTER (WHERE is_late)      AS p_late,
        AVG(repeated)                             AS p_pooled
    FROM samples
    GROUP BY sample
),
tested AS (
    SELECT
        *,
        (p_on_time - p_late)
          / SQRT(p_pooled * (1 - p_pooled) * (1.0 / n_on_time + 1.0 / n_late)) AS z
    FROM rates
)
SELECT
    sample,
    n_on_time,
    ROUND(100 * p_on_time, 2)                        AS on_time_repeat_pct,
    n_late,
    ROUND(100 * p_late, 2)                           AS late_repeat_pct,
    ROUND(z, 2)                                      AS z_score,
    ROUND(erfc(ABS(z)::float8 / SQRT(2))::numeric, 3) AS p_value
FROM tested
ORDER BY sample;

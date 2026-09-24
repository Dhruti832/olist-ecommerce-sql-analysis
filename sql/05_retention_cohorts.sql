-- =============================================================
-- 05 Business Q4: Repeat customers & cohort retention
-- Customer = customer_unique_id (customer_id is per order).
-- Delivered orders only.
-- =============================================================

-- Q12. Repeat-customer rate
WITH customer_orders AS (
    SELECT c.customer_unique_id, COUNT(DISTINCT o.order_id) AS orders
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
)
SELECT
    COUNT(*)                                           AS customers,
    COUNT(*) FILTER (WHERE orders >= 2)                AS repeat_customers,
    ROUND(100.0 * COUNT(*) FILTER (WHERE orders >= 2)
                / COUNT(*), 2)                         AS repeat_rate_pct,
    ROUND(AVG(orders), 3)                              AS avg_orders_per_customer
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
WITH customer_orders AS (
    SELECT
        c.customer_unique_id,
        o.order_id,
        o.order_purchase_timestamp,
        o.order_delivered_customer_date,
        o.order_estimated_delivery_date,
        ROW_NUMBER() OVER (PARTITION BY c.customer_unique_id
                           ORDER BY o.order_purchase_timestamp)  AS order_seq,
        COUNT(*)     OVER (PARTITION BY c.customer_unique_id)    AS total_orders
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
)
SELECT
    CASE WHEN order_delivered_customer_date::date > order_estimated_delivery_date::date
         THEN 'Late first order' ELSE 'On-time first order' END   AS first_order,
    COUNT(*)                                                      AS customers,
    COUNT(*) FILTER (WHERE total_orders >= 2)                     AS repeat_customers,
    ROUND(100.0 * AVG((total_orders >= 2)::int), 2)               AS repeat_rate_pct
FROM customer_orders
WHERE order_seq = 1
GROUP BY 1
ORDER BY 1;

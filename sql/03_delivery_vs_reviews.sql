-- =============================================================
-- 03 Business Q2: Delivery delay vs. review score
-- Delay = actual delivery date - estimated delivery date (in days;
-- negative = early). Delivered orders with a delivery date only.
-- =============================================================

-- Q6. Average review score by delivery-delay bucket
-- 551 orders have more than one review, so reviews are averaged per order
-- first; joining raw reviews would count those orders twice.
WITH order_reviews_agg AS (
    SELECT order_id, AVG(review_score) AS review_score
    FROM order_reviews
    GROUP BY order_id
),
order_delay AS (
    SELECT
        o.order_id,
        o.order_delivered_customer_date::date
          - o.order_estimated_delivery_date::date  AS delay_days,
        r.review_score
    FROM orders o
    JOIN order_reviews_agg r ON r.order_id = o.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
),
bucketed AS (
    SELECT
        *,
        CASE
            WHEN delay_days < 0  THEN '1. Early'
            WHEN delay_days = 0  THEN '2. On time'
            WHEN delay_days <= 3 THEN '3. 1-3 days late'
            WHEN delay_days <= 7 THEN '4. 4-7 days late'
            ELSE                      '5. 7+ days late'
        END AS delay_bucket
    FROM order_delay
)
SELECT
    delay_bucket,
    COUNT(*)                                                  AS orders,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)        AS pct_of_orders,
    ROUND(AVG(review_score), 2)                               AS avg_review_score,
    ROUND(100.0 * AVG((review_score <= 2)::int), 1)           AS pct_1_2_star
FROM bucketed
GROUP BY delay_bucket
ORDER BY delay_bucket;


-- Q6b. Correlation between delay and review score (-1 to 1)
SELECT
    ROUND(CORR(o.order_delivered_customer_date::date
               - o.order_estimated_delivery_date::date,
               r.review_score)::numeric, 3)  AS corr_delay_vs_score
FROM orders o
JOIN (SELECT order_id, AVG(review_score) AS review_score
      FROM order_reviews GROUP BY order_id) r ON r.order_id = o.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL;

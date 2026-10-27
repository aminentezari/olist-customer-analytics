-- 04_business_queries.sql
-- Business queries on the raw tables. Rules from DECISIONS.md:
--   window 2017-01-01 to 2018-08-31, order_status = 'delivered'.

-- Q1.1 Monthly revenue, orders, AOV and month-over-month growth
-- Grain: order. Revenue = SUM(price) of items, freight excluded.
-- Orders without items (no revenue) drop out through the inner join.
WITH order_revenue AS (
    SELECT o.order_id,
           o.order_purchase_timestamp,
           SUM(i.price) AS revenue
    FROM orders o
    JOIN order_items i ON i.order_id = o.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp <  '2018-09-01'
    GROUP BY o.order_id, o.order_purchase_timestamp
),
monthly AS (
    SELECT DATE_TRUNC('month', order_purchase_timestamp)::date AS month,
           COUNT(*)                AS orders,
           ROUND(SUM(revenue), 2)  AS revenue
    FROM order_revenue
    GROUP BY 1
)
SELECT month,
       orders,
       revenue,
       ROUND(revenue / orders, 2) AS aov,
       ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY month))
             / LAG(revenue) OVER (ORDER BY month), 1) AS revenue_mom_pct
FROM monthly
ORDER BY month;

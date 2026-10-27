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

-- Q1.2 Revenue by product category, with rank and share of total
-- Grain: item (a category belongs to a product, and an order can have items
-- from several categories). Revenue = SUM(price), freight excluded.
-- "orders" counts DISTINCT orders per category, so it does not add up to the
-- total number of orders.
WITH item_data AS (
    SELECT i.order_id,
           i.price,
           COALESCE(t.product_category_name_english, 'unknown') AS category
    FROM order_items i
    JOIN orders o        ON o.order_id = i.order_id
    LEFT JOIN products p ON p.product_id = i.product_id
    LEFT JOIN product_category_translation t
           ON t.product_category_name = p.product_category_name
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp <  '2018-09-01'
)
SELECT RANK() OVER (ORDER BY SUM(price) DESC)                 AS rank,
       category,
       COUNT(DISTINCT order_id)                               AS orders,
       ROUND(SUM(price), 2)                                   AS revenue,
       ROUND(100.0 * SUM(price) / SUM(SUM(price)) OVER (), 1) AS pct_of_revenue
FROM item_data
GROUP BY category
ORDER BY rank
LIMIT 15;

-- Q1.3 Revenue by customer state, with rank and share of total
-- Grain: order. Revenue = SUM(price) of items per order, then summed by state.
WITH order_revenue AS (
    SELECT o.order_id,
           c.customer_state,
           SUM(i.price) AS revenue
    FROM orders o
    JOIN customers c   ON c.customer_id = o.customer_id
    JOIN order_items i ON i.order_id = o.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp <  '2018-09-01'
    GROUP BY o.order_id, c.customer_state
)
SELECT RANK() OVER (ORDER BY SUM(revenue) DESC)                 AS rank,
       customer_state,
       COUNT(*)                                                 AS orders,
       ROUND(SUM(revenue), 2)                                   AS revenue,
       ROUND(100.0 * SUM(revenue) / SUM(SUM(revenue)) OVER (), 1) AS pct_of_revenue,
       ROUND(SUM(revenue) / COUNT(*), 2)                        AS aov
FROM order_revenue
GROUP BY customer_state
ORDER BY rank;

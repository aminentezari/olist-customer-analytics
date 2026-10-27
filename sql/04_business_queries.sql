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

-- Q3.1 Delivery performance by month
-- Grain: order. Only delivered orders with a delivery date, in the window.
-- Late = delivered on a later DATE than the estimated date. We compare dates,
-- not timestamps, because the estimate is a date and delivery has a time.
WITH delivery AS (
    SELECT o.order_id,
           o.order_purchase_timestamp,
           (o.order_delivered_customer_date::date - o.order_estimated_delivery_date::date) AS days_vs_estimate,
           EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_purchase_timestamp)) / 86400.0 AS delivery_days
    FROM orders o
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp <  '2018-09-01'
)
SELECT DATE_TRUNC('month', order_purchase_timestamp)::date AS month,
       COUNT(*)                                            AS orders,
       ROUND(AVG(delivery_days), 1)                        AS avg_delivery_days,
       ROUND(100.0 * COUNT(*) FILTER (WHERE days_vs_estimate > 0) / COUNT(*), 1) AS late_pct
FROM delivery
GROUP BY 1
ORDER BY 1;

-- Q3.2 Delivery performance by customer state
-- Same grain and filters as Q3.1. Small states have few orders: read with care.
WITH delivery AS (
    SELECT o.order_id,
           c.customer_state,
           (o.order_delivered_customer_date::date - o.order_estimated_delivery_date::date) AS days_vs_estimate,
           EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_purchase_timestamp)) / 86400.0 AS delivery_days
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp <  '2018-09-01'
)
SELECT customer_state,
       COUNT(*)                                     AS orders,
       ROUND(AVG(delivery_days), 1)                 AS avg_delivery_days,
       ROUND(100.0 * COUNT(*) FILTER (WHERE days_vs_estimate > 0) / COUNT(*), 1) AS late_pct
FROM delivery
GROUP BY customer_state
ORDER BY late_pct DESC;

-- Q3.3 Average review score and % bad reviews by delay bucket
-- Grain: order. One review per order: the latest by review_creation_date,
-- ties broken by review_answer_timestamp (rule from DECISIONS.md).
-- Orders without a review drop out through the inner join.
-- Bad review = score 1 or 2.
WITH latest_review AS (
    SELECT DISTINCT ON (order_id)
           order_id, review_score
    FROM order_reviews
    ORDER BY order_id, review_creation_date DESC, review_answer_timestamp DESC
),
delivery AS (
    SELECT o.order_id,
           (o.order_delivered_customer_date::date - o.order_estimated_delivery_date::date) AS days_vs_estimate
    FROM orders o
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp <  '2018-09-01'
),
bucketed AS (
    SELECT d.order_id,
           r.review_score,
           CASE WHEN d.days_vs_estimate < 0              THEN '1 early'
                WHEN d.days_vs_estimate = 0              THEN '2 on time'
                WHEN d.days_vs_estimate BETWEEN 1 AND 3  THEN '3 late 1-3 days'
                WHEN d.days_vs_estimate BETWEEN 4 AND 7  THEN '4 late 4-7 days'
                ELSE                                          '5 late 8+ days'
           END AS delay_bucket
    FROM delivery d
    JOIN latest_review r ON r.order_id = d.order_id
)
SELECT delay_bucket,
       COUNT(*)                                                   AS orders,
       ROUND(AVG(review_score), 2)                                AS avg_review,
       ROUND(100.0 * COUNT(*) FILTER (WHERE review_score <= 2) / COUNT(*), 1) AS pct_bad_reviews
FROM bucketed
GROUP BY delay_bucket
ORDER BY delay_bucket;

-- Q4 base: one row per (seller, order) with a review.
-- Grain: seller-order. An order with items from 2 sellers appears twice, and
-- its single review counts for both sellers (the review is about the order,
-- we cannot split it). Revenue = SUM(price) of that seller's items.
-- Delivered orders with a delivery date, in the window, with a review.
-- One review per order: latest by review_creation_date (DECISIONS.md).
-- A temp view lives only for this psql session, it does not change the database.
CREATE OR REPLACE TEMP VIEW seller_order_base AS
WITH latest_review AS (
    SELECT DISTINCT ON (order_id) order_id, review_score
    FROM order_reviews
    ORDER BY order_id, review_creation_date DESC, review_answer_timestamp DESC
)
SELECT i.seller_id,
       o.order_id,
       SUM(i.price) AS revenue,
       (o.order_delivered_customer_date::date - o.order_estimated_delivery_date::date) AS days_vs_estimate,
       r.review_score
FROM order_items i
JOIN orders o        ON o.order_id = i.order_id
JOIN latest_review r ON r.order_id = o.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_purchase_timestamp >= '2017-01-01'
  AND o.order_purchase_timestamp <  '2018-09-01'
GROUP BY i.seller_id, o.order_id, o.order_delivered_customer_date,
         o.order_estimated_delivery_date, r.review_score;

-- Q4.1 Seller scorecard: sellers with the MOST bad reviews (volume view)
SELECT b.seller_id,
       s.seller_state,
       COUNT(*)                                                        AS orders,
       ROUND(SUM(b.revenue), 2)                                        AS revenue,
       ROUND(100.0 * COUNT(*) FILTER (WHERE b.days_vs_estimate > 0) / COUNT(*), 1) AS late_pct,
       ROUND(AVG(b.review_score), 2)                                   AS avg_review,
       COUNT(*) FILTER (WHERE b.review_score <= 2)                     AS bad_reviews,
       ROUND(100.0 * COUNT(*) FILTER (WHERE b.review_score <= 2) / COUNT(*), 1) AS pct_bad
FROM seller_order_base b
JOIN sellers s ON s.seller_id = b.seller_id
GROUP BY b.seller_id, s.seller_state
ORDER BY bad_reviews DESC
LIMIT 15;

-- Q4.2 Seller scorecard: WORST bad-review RATE, only sellers with 50+ orders
-- The minimum avoids tiny sellers (2 orders, 1 bad review = 50%) topping the list.
SELECT b.seller_id,
       s.seller_state,
       COUNT(*)                                                        AS orders,
       ROUND(100.0 * COUNT(*) FILTER (WHERE b.days_vs_estimate > 0) / COUNT(*), 1) AS late_pct,
       ROUND(AVG(b.review_score), 2)                                   AS avg_review,
       ROUND(100.0 * COUNT(*) FILTER (WHERE b.review_score <= 2) / COUNT(*), 1) AS pct_bad
FROM seller_order_base b
JOIN sellers s ON s.seller_id = b.seller_id
GROUP BY b.seller_id, s.seller_state
HAVING COUNT(*) >= 50
ORDER BY pct_bad DESC
LIMIT 15;

-- Q4.3 Categories: bad reviews by category, only categories with 100+ orders
-- Grain: category-order (an order with 2 categories counts in both, and its
-- review counts for both, same logic as the seller view).
WITH latest_review AS (
    SELECT DISTINCT ON (order_id) order_id, review_score
    FROM order_reviews
    ORDER BY order_id, review_creation_date DESC, review_answer_timestamp DESC
),
category_orders AS (
    SELECT DISTINCT
           i.order_id,
           COALESCE(t.product_category_name_english, 'unknown') AS category,
           r.review_score
    FROM order_items i
    JOIN orders o        ON o.order_id = i.order_id
    JOIN latest_review r ON r.order_id = o.order_id
    LEFT JOIN products p ON p.product_id = i.product_id
    LEFT JOIN product_category_translation t
           ON t.product_category_name = p.product_category_name
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp <  '2018-09-01'
)
SELECT category,
       COUNT(*)                                                        AS orders,
       ROUND(AVG(review_score), 2)                                     AS avg_review,
       COUNT(*) FILTER (WHERE review_score <= 2)                       AS bad_reviews,
       ROUND(100.0 * COUNT(*) FILTER (WHERE review_score <= 2) / COUNT(*), 1) AS pct_bad
FROM category_orders
GROUP BY category
HAVING COUNT(*) >= 100
ORDER BY pct_bad DESC
LIMIT 15;

-- Q5.1 Repeat purchase rate
-- Grain: customer (customer_unique_id). Delivered orders in the window.
-- Repeat customer = 2 or more delivered orders in the window.
WITH cust_orders AS (
    SELECT c.customer_unique_id, COUNT(*) AS n_orders
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp <  '2018-09-01'
    GROUP BY c.customer_unique_id
)
SELECT COUNT(*)                                          AS customers,
       COUNT(*) FILTER (WHERE n_orders >= 2)             AS repeat_customers,
       ROUND(100.0 * COUNT(*) FILTER (WHERE n_orders >= 2) / COUNT(*), 2) AS repeat_rate_pct
FROM cust_orders;

-- Q5.2 Cohort retention by first-purchase month
-- Grain: customer. Cohort = month of the customer's first delivered order.
-- months_since_first = months between the first order and a later order.
-- Shows, for each cohort, how many customers ordered again in month +1, +2...
WITH orders_c AS (
    SELECT c.customer_unique_id,
           DATE_TRUNC('month', o.order_purchase_timestamp)::date AS order_month
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp <  '2018-09-01'
),
first_month AS (
    SELECT customer_unique_id, MIN(order_month) AS cohort_month
    FROM orders_c
    GROUP BY customer_unique_id
),
activity AS (
    SELECT f.cohort_month,
           (EXTRACT(YEAR FROM o.order_month) - EXTRACT(YEAR FROM f.cohort_month)) * 12
         + (EXTRACT(MONTH FROM o.order_month) - EXTRACT(MONTH FROM f.cohort_month)) AS months_since_first,
           o.customer_unique_id
    FROM orders_c o
    JOIN first_month f USING (customer_unique_id)
)
SELECT cohort_month,
       COUNT(DISTINCT customer_unique_id) FILTER (WHERE months_since_first = 0) AS cohort_size,
       COUNT(DISTINCT customer_unique_id) FILTER (WHERE months_since_first = 1) AS m1,
       COUNT(DISTINCT customer_unique_id) FILTER (WHERE months_since_first = 3) AS m3,
       COUNT(DISTINCT customer_unique_id) FILTER (WHERE months_since_first = 6) AS m6
FROM activity
GROUP BY cohort_month
ORDER BY cohort_month;

-- Q5.3 Payment types and installments
-- Grain: payment row (an order can have several payments).
-- Share is by number of payments and by value.
SELECT p.payment_type,
       COUNT(*)                                                   AS payments,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)         AS pct_payments,
       ROUND(SUM(p.payment_value), 2)                             AS total_value,
       ROUND(AVG(p.payment_installments), 1)                      AS avg_installments
FROM order_payments p
JOIN orders o ON o.order_id = p.order_id
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp >= '2017-01-01'
  AND o.order_purchase_timestamp <  '2018-09-01'
GROUP BY p.payment_type
ORDER BY payments DESC;

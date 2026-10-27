-- 05_views.sql
-- Star schema for Power BI. Rules from DECISIONS.md are applied here once.

-- dim_customer: one row per order-level customer_id (the key used by orders),
-- with the real customer id (customer_unique_id) alongside.
CREATE OR REPLACE VIEW dim_customer AS
SELECT customer_id,
       customer_unique_id,
       customer_city,
       customer_state
FROM customers;

-- dim_product: one row per product, with English category and 'unknown' fallback.
CREATE OR REPLACE VIEW dim_product AS
SELECT p.product_id,
       COALESCE(t.product_category_name_english, 'unknown') AS category,
       p.product_weight_g,
       p.product_photos_qty
FROM products p
LEFT JOIN product_category_translation t
       ON t.product_category_name = p.product_category_name;

-- dim_seller: one row per seller.
CREATE OR REPLACE VIEW dim_seller AS
SELECT seller_id,
       seller_city,
       seller_state
FROM sellers;

-- dim_date: one row per calendar day in the analysis window.
-- Built with integer date arithmetic: no time zone effects, no lost days.
CREATE OR REPLACE VIEW dim_date AS
SELECT d                                    AS date,
       EXTRACT(YEAR FROM d)::int            AS year,
       EXTRACT(MONTH FROM d)::int           AS month,
       TO_CHAR(d, 'Mon')                    AS month_name,
       DATE_TRUNC('month', d)::date         AS month_start,
       'Q' || EXTRACT(QUARTER FROM d)::int  AS quarter
FROM (SELECT ('2017-01-01'::date + n) AS d
      FROM generate_series(0, DATE '2018-08-31' - DATE '2017-01-01') AS n) x;

-- fact_orders: ONE ROW PER ORDER (grain = order).
-- Window 2017-01-01 to 2018-08-31, delivered orders only (DECISIONS.md).
-- One review per order: latest by review_creation_date.
-- revenue = SUM(price) of items, freight_value = SUM(freight), n_items, n_sellers.
-- Delivery columns are NULL when there is no delivery date.
CREATE OR REPLACE VIEW fact_orders AS
WITH latest_review AS (
    SELECT DISTINCT ON (order_id) order_id, review_score
    FROM order_reviews
    ORDER BY order_id, review_creation_date DESC, review_answer_timestamp DESC
),
items AS (
    SELECT order_id,
           SUM(price)                AS revenue,
           SUM(freight_value)        AS freight_value,
           COUNT(*)                  AS n_items,
           COUNT(DISTINCT seller_id) AS n_sellers
    FROM order_items
    GROUP BY order_id
),
pay AS (
    SELECT order_id,
           MAX(payment_installments) AS installments,
           (ARRAY_AGG(payment_type ORDER BY payment_value DESC))[1] AS main_payment_type
    FROM order_payments
    GROUP BY order_id
)
SELECT o.order_id,
       o.customer_id,
       o.order_purchase_timestamp::date AS order_date,
       o.order_delivered_customer_date::date AS delivered_date,
       o.order_estimated_delivery_date::date AS estimated_date,
       i.revenue,
       i.freight_value,
       i.n_items,
       i.n_sellers,
       p.main_payment_type,
       p.installments,
       r.review_score,
       (r.review_score <= 2) AS is_bad_review,
       CASE WHEN o.order_delivered_customer_date IS NULL THEN NULL
            ELSE o.order_delivered_customer_date::date - o.order_estimated_delivery_date::date
       END AS days_vs_estimate,
       CASE WHEN o.order_delivered_customer_date IS NULL THEN NULL
            ELSE (o.order_delivered_customer_date::date > o.order_estimated_delivery_date::date)
       END AS is_late,
       CASE WHEN o.order_delivered_customer_date IS NULL THEN NULL
            WHEN o.order_delivered_customer_date::date - o.order_estimated_delivery_date::date < 0 THEN '1 Early'
            WHEN o.order_delivered_customer_date::date - o.order_estimated_delivery_date::date = 0 THEN '2 On time'
            WHEN o.order_delivered_customer_date::date - o.order_estimated_delivery_date::date <= 3 THEN '3 Late 1-3 days'
            WHEN o.order_delivered_customer_date::date - o.order_estimated_delivery_date::date <= 7 THEN '4 Late 4-7 days'
            ELSE '5 Late 8+ days'
       END AS delay_bucket,
       EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_purchase_timestamp)) / 86400.0 AS delivery_days
FROM orders o
JOIN items i             ON i.order_id = o.order_id
LEFT JOIN latest_review r ON r.order_id = o.order_id
LEFT JOIN pay p           ON p.order_id = o.order_id
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp >= '2017-01-01'
  AND o.order_purchase_timestamp <  '2018-09-01';

-- fact_order_items: ONE ROW PER ITEM (grain = order item).
-- Same order filter as fact_orders, so both facts cover the same orders.
CREATE OR REPLACE VIEW fact_order_items AS
SELECT i.order_id,
       i.order_item_id,
       i.product_id,
       i.seller_id,
       i.price,
       i.freight_value
FROM order_items i
JOIN fact_orders f ON f.order_id = i.order_id;

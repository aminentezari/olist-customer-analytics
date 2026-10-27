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
CREATE OR REPLACE VIEW dim_date AS
SELECT d::date                              AS date,
       EXTRACT(YEAR FROM d)::int            AS year,
       EXTRACT(MONTH FROM d)::int           AS month,
       TO_CHAR(d, 'Mon')                    AS month_name,
       DATE_TRUNC('month', d)::date         AS month_start,
       'Q' || EXTRACT(QUARTER FROM d)::int  AS quarter
FROM generate_series('2017-01-01'::date, '2018-08-31'::date, interval '1 day') AS d;

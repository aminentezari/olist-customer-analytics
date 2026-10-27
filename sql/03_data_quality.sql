-- 03_data_quality.sql
-- Data quality checks on the raw tables. Each check returns numbers to read,
-- the decisions we take from them go in the README.

-- 1. Orders by status (which orders count as "delivered"?)
SELECT order_status, COUNT(*) AS n
FROM orders
GROUP BY order_status
ORDER BY n DESC;

-- 2. NULLs in the key date columns of orders
SELECT
    COUNT(*) FILTER (WHERE order_approved_at IS NULL)             AS null_approved,
    COUNT(*) FILTER (WHERE order_delivered_carrier_date IS NULL)  AS null_carrier,
    COUNT(*) FILTER (WHERE order_delivered_customer_date IS NULL) AS null_delivered,
    COUNT(*) FILTER (WHERE order_estimated_delivery_date IS NULL) AS null_estimated
FROM orders;

-- 3. Delivered orders that still have no delivery date
SELECT COUNT(*) AS delivered_without_date
FROM orders
WHERE order_status = 'delivered' AND order_delivered_customer_date IS NULL;

-- 4. Date logic: delivered before purchase, or before carrier pickup
SELECT
    COUNT(*) FILTER (WHERE order_delivered_customer_date < order_purchase_timestamp)     AS delivered_before_purchase,
    COUNT(*) FILTER (WHERE order_delivered_customer_date < order_delivered_carrier_date) AS delivered_before_carrier,
    COUNT(*) FILTER (WHERE order_approved_at < order_purchase_timestamp)                 AS approved_before_purchase
FROM orders;

-- 5. Customers: rows vs real customers (repeat purchase potential)
SELECT COUNT(*) AS customer_ids,
       COUNT(DISTINCT customer_unique_id) AS unique_customers
FROM customers;

-- 6. Reviews: duplicated review_id, and orders with more than one review
SELECT COUNT(*) - COUNT(DISTINCT review_id) AS duplicate_review_ids
FROM order_reviews;

SELECT COUNT(*) AS orders_with_multiple_reviews
FROM (SELECT order_id FROM order_reviews GROUP BY order_id HAVING COUNT(*) > 1) t;

-- 7. Review score values (should be only 1 to 5)
SELECT review_score, COUNT(*) AS n
FROM order_reviews
GROUP BY review_score
ORDER BY review_score;

-- 8. Orders with no items, and orders with no review
SELECT
    (SELECT COUNT(*) FROM orders o
      WHERE NOT EXISTS (SELECT 1 FROM order_items i WHERE i.order_id = o.order_id)) AS orders_without_items,
    (SELECT COUNT(*) FROM orders o
      WHERE NOT EXISTS (SELECT 1 FROM order_reviews r WHERE r.order_id = o.order_id)) AS orders_without_review;

-- 9. Products: NULL categories, and categories missing from the translation table
SELECT
    COUNT(*) FILTER (WHERE product_category_name IS NULL) AS null_category,
    COUNT(*) FILTER (WHERE product_category_name IS NOT NULL
        AND product_category_name NOT IN
            (SELECT product_category_name FROM product_category_translation)) AS no_translation
FROM products;

-- 10. Price and freight sanity
SELECT MIN(price) AS min_price, MAX(price) AS max_price,
       COUNT(*) FILTER (WHERE price <= 0)        AS zero_or_negative_price,
       COUNT(*) FILTER (WHERE freight_value < 0) AS negative_freight
FROM order_items;

-- 11. Monthly order counts, to choose the clean analysis window
SELECT DATE_TRUNC('month', order_purchase_timestamp)::date AS month,
       COUNT(*) AS orders
FROM orders
GROUP BY 1
ORDER BY 1;

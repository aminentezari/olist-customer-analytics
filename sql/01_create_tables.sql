-- 01_create_tables.sql
-- Raw tables for the Olist dataset. Column names match the CSV headers
-- (including the original "lenght" misspelling in products) so loading is
-- a straight copy. Cleaning and renaming happen later, in the views.

DROP TABLE IF EXISTS order_reviews, order_payments, order_items,
    orders, products, sellers, customers, geolocation,
    product_category_translation CASCADE;

CREATE TABLE customers (
    customer_id              TEXT PRIMARY KEY,   -- unique PER ORDER
    customer_unique_id       TEXT NOT NULL,      -- the real customer
    customer_zip_code_prefix CHAR(5),
    customer_city            TEXT,
    customer_state           CHAR(2)
);

CREATE TABLE sellers (
    seller_id              TEXT PRIMARY KEY,
    seller_zip_code_prefix CHAR(5),
    seller_city            TEXT,
    seller_state           CHAR(2)
);

CREATE TABLE products (
    product_id                 TEXT PRIMARY KEY,
    product_category_name      TEXT,
    product_name_lenght        INT,
    product_description_lenght INT,
    product_photos_qty         INT,
    product_weight_g           INT,
    product_length_cm          INT,
    product_height_cm          INT,
    product_width_cm           INT
);

CREATE TABLE product_category_translation (
    product_category_name         TEXT PRIMARY KEY,
    product_category_name_english TEXT
);

-- No primary key: many rows per zip prefix. We aggregate it before joining.
CREATE TABLE geolocation (
    geolocation_zip_code_prefix CHAR(5),
    geolocation_lat             DOUBLE PRECISION,
    geolocation_lng             DOUBLE PRECISION,
    geolocation_city            TEXT,
    geolocation_state           CHAR(2)
);

CREATE TABLE orders (
    order_id                      TEXT PRIMARY KEY,
    customer_id                   TEXT NOT NULL REFERENCES customers(customer_id),
    order_status                  TEXT,
    order_purchase_timestamp      TIMESTAMP,
    order_approved_at             TIMESTAMP,
    order_delivered_carrier_date  TIMESTAMP,
    order_delivered_customer_date TIMESTAMP,
    order_estimated_delivery_date TIMESTAMP
);

-- Grain: one row per item inside an order.
CREATE TABLE order_items (
    order_id            TEXT NOT NULL REFERENCES orders(order_id),
    order_item_id       INT  NOT NULL,
    product_id          TEXT REFERENCES products(product_id),
    seller_id           TEXT REFERENCES sellers(seller_id),
    shipping_limit_date TIMESTAMP,
    price               NUMERIC(10,2),
    freight_value       NUMERIC(10,2),
    PRIMARY KEY (order_id, order_item_id)
);

-- Grain: one row per payment (an order can have several).
CREATE TABLE order_payments (
    order_id             TEXT NOT NULL REFERENCES orders(order_id),
    payment_sequential   INT  NOT NULL,
    payment_type         TEXT,
    payment_installments INT,
    payment_value        NUMERIC(10,2),
    PRIMARY KEY (order_id, payment_sequential)
);

-- No primary key on purpose: review_id has duplicates in the raw data.
-- We check this in 03_data_quality.sql and choose a rule there.
CREATE TABLE order_reviews (
    review_id               TEXT,
    order_id                TEXT NOT NULL REFERENCES orders(order_id),
    review_score            INT,
    review_comment_title    TEXT,
    review_comment_message  TEXT,
    review_creation_date    TIMESTAMP,
    review_answer_timestamp TIMESTAMP
);

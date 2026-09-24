-- =============================================================
-- Olist E-commerce: database schema (PostgreSQL)
-- Source: kaggle.com/datasets/olistbr/brazilian-ecommerce
-- Run order: this file first, then python/load_data.py
-- =============================================================

DROP TABLE IF EXISTS order_reviews, order_payments, order_items, orders,
                     products, sellers, customers, category_translation,
                     geolocation CASCADE;

-- ---------- Dimension tables ----------

-- One row per ORDER's customer record. The real person is customer_unique_id
-- (one person can have many customer_ids).
CREATE TABLE customers (
    customer_id              VARCHAR(32) PRIMARY KEY,
    customer_unique_id       VARCHAR(32) NOT NULL,
    customer_zip_code_prefix VARCHAR(5)  NOT NULL,   -- text, keeps leading zeros
    customer_city            VARCHAR(50) NOT NULL,
    customer_state           CHAR(2)     NOT NULL
);

CREATE TABLE sellers (
    seller_id              VARCHAR(32) PRIMARY KEY,
    seller_zip_code_prefix VARCHAR(5)  NOT NULL,
    seller_city            VARCHAR(50) NOT NULL,
    seller_state           CHAR(2)     NOT NULL
);

-- Portuguese -> English category names.
-- Note: 2 categories in products are missing here (pc_gamer,
-- portateis_cozinha_e_preparadores_de_alimentos), so products has no FK to it.
CREATE TABLE category_translation (
    product_category_name         VARCHAR(60) PRIMARY KEY,
    product_category_name_english VARCHAR(60) NOT NULL
);

-- Source column typos (lenght) are fixed to "length" during load.
CREATE TABLE products (
    product_id                 VARCHAR(32) PRIMARY KEY,
    product_category_name      VARCHAR(60),          -- 610 NULLs
    product_name_length        INTEGER,
    product_description_length INTEGER,
    product_photos_qty         INTEGER,
    product_weight_g           INTEGER,
    product_length_cm          INTEGER,
    product_height_cm          INTEGER,
    product_width_cm           INTEGER
);

-- Raw file has ~1M rows with many per zip prefix; loaded as one averaged
-- point per prefix (for maps). Not FK-linked: some prefixes are missing.
CREATE TABLE geolocation (
    zip_code_prefix VARCHAR(5) PRIMARY KEY,
    lat             NUMERIC(9,6) NOT NULL,
    lng             NUMERIC(9,6) NOT NULL,
    city            VARCHAR(50),
    state           CHAR(2)
);

-- ---------- Fact tables ----------

-- One row per order.
CREATE TABLE orders (
    order_id                      VARCHAR(32) PRIMARY KEY,
    customer_id                   VARCHAR(32) NOT NULL UNIQUE REFERENCES customers,
    order_status                  VARCHAR(12) NOT NULL,
    order_purchase_timestamp      TIMESTAMP   NOT NULL,
    order_approved_at             TIMESTAMP,
    order_delivered_carrier_date  TIMESTAMP,
    order_delivered_customer_date TIMESTAMP,
    order_estimated_delivery_date TIMESTAMP   NOT NULL
);

-- One row per item line in an order (an order can have several).
CREATE TABLE order_items (
    order_id            VARCHAR(32)   NOT NULL REFERENCES orders,
    order_item_id       SMALLINT      NOT NULL,
    product_id          VARCHAR(32)   NOT NULL REFERENCES products,
    seller_id           VARCHAR(32)   NOT NULL REFERENCES sellers,
    shipping_limit_date TIMESTAMP     NOT NULL,
    price               NUMERIC(10,2) NOT NULL,
    freight_value       NUMERIC(10,2) NOT NULL,
    PRIMARY KEY (order_id, order_item_id)
);

-- One row per payment (an order can be split across several).
CREATE TABLE order_payments (
    order_id             VARCHAR(32)   NOT NULL REFERENCES orders,
    payment_sequential   SMALLINT      NOT NULL,
    payment_type         VARCHAR(20)   NOT NULL,
    payment_installments SMALLINT      NOT NULL,
    payment_value        NUMERIC(10,2) NOT NULL,
    PRIMARY KEY (order_id, payment_sequential)
);

-- review_id alone is NOT unique (814 dupes), and 551 orders have >1 review.
CREATE TABLE order_reviews (
    review_id               VARCHAR(32) NOT NULL,
    order_id                VARCHAR(32) NOT NULL REFERENCES orders,
    review_score            SMALLINT    NOT NULL CHECK (review_score BETWEEN 1 AND 5),
    review_comment_title    TEXT,
    review_comment_message  TEXT,
    review_creation_date    TIMESTAMP   NOT NULL,
    review_answer_timestamp TIMESTAMP   NOT NULL,
    PRIMARY KEY (review_id, order_id)
);

-- ---------- Indexes on common join/filter columns ----------
CREATE INDEX idx_customers_unique_id  ON customers (customer_unique_id);
CREATE INDEX idx_orders_purchase_ts   ON orders (order_purchase_timestamp);
CREATE INDEX idx_order_items_product  ON order_items (product_id);
CREATE INDEX idx_order_items_seller   ON order_items (seller_id);
CREATE INDEX idx_order_reviews_order  ON order_reviews (order_id);

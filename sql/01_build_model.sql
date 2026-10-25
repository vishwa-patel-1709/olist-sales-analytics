-- =====================================================================
-- Olist E-Commerce | 01_build_model.sql
-- Cleans the raw tables and builds a star schema for Power BI:
--   fact_orders, fact_order_items, dim_customers, dim_products, dim_sellers
-- Analysis window: Jan 2017 - Aug 2018 (edge months have too little data)
-- =====================================================================

-- Product categories in English; missing categories -> 'unknown'
CREATE OR REPLACE TABLE dim_products AS
SELECT
    p.product_id,
    COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS category,
    p.product_weight_g,
    p.product_photos_qty
FROM products p
LEFT JOIN product_category_name_translation t
       ON p.product_category_name = t.product_category_name;

-- Order-level fact table (one row per order)
CREATE OR REPLACE TABLE fact_orders AS
WITH items AS (
    SELECT order_id,
           COUNT(*)            AS item_count,
           SUM(price)          AS product_revenue,
           SUM(freight_value)  AS freight_revenue
    FROM order_items
    GROUP BY order_id
),
pay AS (
    SELECT order_id,
           SUM(payment_value)  AS payment_value,
           -- main payment method = the one that paid the most
           ARG_MAX(payment_type, payment_value) AS payment_type,
           MAX(payment_installments) AS installments
    FROM order_payments
    GROUP BY order_id
),
rev AS (   -- a few orders have more than one review -> average them
    SELECT order_id, AVG(review_score) AS review_score
    FROM order_reviews
    GROUP BY order_id
)
SELECT
    o.order_id,
    c.customer_unique_id,
    o.order_status,
    CAST(o.order_purchase_timestamp AS DATE)              AS order_date,
    DATE_TRUNC('month', o.order_purchase_timestamp)::DATE AS order_month,
    CAST(o.order_delivered_customer_date AS DATE)         AS delivered_date,
    CAST(o.order_estimated_delivery_date AS DATE)         AS estimated_date,
    DATE_DIFF('day', o.order_purchase_timestamp, o.order_delivered_customer_date) AS delivery_days,
    CASE WHEN o.order_delivered_customer_date IS NULL THEN NULL
         WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date + INTERVAL 1 DAY THEN 1
         ELSE 0 END                                       AS is_late,
    CASE WHEN o.order_status = 'delivered' THEN 1 ELSE 0 END AS is_delivered,
    CASE WHEN o.order_status IN ('canceled', 'unavailable') THEN 1 ELSE 0 END AS is_canceled,
    COALESCE(i.item_count, 0)        AS item_count,
    COALESCE(i.product_revenue, 0)   AS product_revenue,
    COALESCE(i.freight_revenue, 0)   AS freight_revenue,
    p.payment_value,
    p.payment_type,
    p.installments,
    r.review_score
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id       -- map to the real person
LEFT JOIN items i ON o.order_id = i.order_id
LEFT JOIN pay   p ON o.order_id = p.order_id
LEFT JOIN rev   r ON o.order_id = r.order_id
WHERE o.order_purchase_timestamp >= '2017-01-01'
  AND o.order_purchase_timestamp <  '2018-09-01';

-- Item-level fact table (one row per product sold) - for category & seller analysis
CREATE OR REPLACE TABLE fact_order_items AS
SELECT
    oi.order_id,
    oi.order_item_id,
    oi.product_id,
    oi.seller_id,
    f.customer_unique_id,
    f.order_date,
    f.order_month,
    f.is_delivered,
    oi.price,
    oi.freight_value
FROM order_items oi
JOIN fact_orders f ON oi.order_id = f.order_id;

-- Customer dimension: one row per real person (customer_unique_id)
CREATE OR REPLACE TABLE dim_customers AS
WITH loc AS (   -- a person can have several customer_ids; take their latest location
    SELECT c.customer_unique_id,
           ARG_MAX(c.customer_city,  o.order_purchase_timestamp) AS city,
           ARG_MAX(c.customer_state, o.order_purchase_timestamp) AS state
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    GROUP BY c.customer_unique_id
),
stats AS (
    SELECT customer_unique_id,
           MIN(order_date)                 AS first_order_date,
           MIN(order_month)                AS cohort_month,
           MAX(order_date)                 AS last_order_date,
           COUNT(*)                        AS total_orders,
           SUM(product_revenue + freight_revenue) AS lifetime_revenue
    FROM fact_orders
    WHERE is_delivered = 1
    GROUP BY customer_unique_id
)
SELECT l.customer_unique_id, l.city, l.state,
       s.first_order_date, s.cohort_month, s.last_order_date,
       COALESCE(s.total_orders, 0)     AS total_orders,
       COALESCE(s.lifetime_revenue, 0) AS lifetime_revenue,
       CASE WHEN s.total_orders > 1 THEN 1 ELSE 0 END AS is_repeat_customer
FROM loc l
LEFT JOIN stats s ON l.customer_unique_id = s.customer_unique_id
WHERE l.customer_unique_id IN (SELECT customer_unique_id FROM fact_orders);

-- Seller dimension
CREATE OR REPLACE TABLE dim_sellers AS
SELECT seller_id, seller_city, seller_state
FROM sellers;

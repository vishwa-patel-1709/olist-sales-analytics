-- =====================================================================
-- Olist E-Commerce | 02_business_questions.sql
-- Business questions answered with SQL. Revenue = delivered orders only,
-- price + freight. Window: Jan 2017 - Aug 2018.
-- Each query starts with a "-- Qn:" line; run_analysis.py uses it as the title.
-- =====================================================================

-- Q1: Headline KPIs
SELECT
    COUNT(*)                                             AS delivered_orders,
    COUNT(DISTINCT customer_unique_id)                   AS customers,
    ROUND(SUM(product_revenue + freight_revenue), 0)     AS total_revenue,
    ROUND(AVG(product_revenue + freight_revenue), 2)     AS avg_order_value,
    ROUND(AVG(review_score), 2)                          AS avg_review_score,
    ROUND(100.0 * AVG(is_late), 1)                       AS late_delivery_pct,
    ROUND(AVG(delivery_days), 1)                         AS avg_delivery_days
FROM fact_orders
WHERE is_delivered = 1;

-- Q2: Monthly revenue, orders, AOV and month-over-month growth
WITH m AS (
    SELECT order_month,
           COUNT(*) AS orders,
           SUM(product_revenue + freight_revenue) AS revenue
    FROM fact_orders
    WHERE is_delivered = 1
    GROUP BY order_month
)
SELECT order_month,
       orders,
       ROUND(revenue, 0)          AS revenue,
       ROUND(revenue / orders, 2) AS aov,
       ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY order_month))
             / LAG(revenue) OVER (ORDER BY order_month), 1) AS mom_growth_pct
FROM m
ORDER BY order_month;

-- Q3: Top 10 product categories by revenue (and their share of total)
SELECT p.category,
       COUNT(DISTINCT i.order_id)                    AS orders,
       ROUND(SUM(i.price + i.freight_value), 0)      AS revenue,
       ROUND(100.0 * SUM(i.price + i.freight_value)
             / SUM(SUM(i.price + i.freight_value)) OVER (), 1) AS revenue_share_pct
FROM fact_order_items i
JOIN dim_products p ON i.product_id = p.product_id
WHERE i.is_delivered = 1
GROUP BY p.category
ORDER BY revenue DESC
LIMIT 10;

-- Q4: How many customers come back? (repeat purchase rate)
SELECT
    COUNT(*)                                      AS customers,
    SUM(is_repeat_customer)                       AS repeat_customers,
    ROUND(100.0 * AVG(is_repeat_customer), 2)     AS repeat_rate_pct,
    ROUND(AVG(CASE WHEN is_repeat_customer = 1 THEN lifetime_revenue END), 2) AS avg_ltv_repeat,
    ROUND(AVG(CASE WHEN is_repeat_customer = 0 THEN lifetime_revenue END), 2) AS avg_ltv_one_time
FROM dim_customers
WHERE total_orders > 0;

-- Q5: Cohort retention - % of each monthly cohort that bought again within 1, 3 and 6 months
WITH firsts AS (
    SELECT customer_unique_id, cohort_month, first_order_date
    FROM dim_customers WHERE total_orders > 0
),
later AS (
    SELECT f.customer_unique_id,
           MIN(o.order_date) AS second_order_date
    FROM firsts f
    JOIN fact_orders o
      ON o.customer_unique_id = f.customer_unique_id
     AND o.is_delivered = 1
     AND o.order_date > f.first_order_date
    GROUP BY f.customer_unique_id
)
SELECT f.cohort_month,
       COUNT(*) AS new_customers,
       ROUND(100.0 * COUNT(CASE WHEN l.second_order_date <= f.first_order_date + INTERVAL 30  DAY THEN 1 END) / COUNT(*), 2) AS returned_30d_pct,
       ROUND(100.0 * COUNT(CASE WHEN l.second_order_date <= f.first_order_date + INTERVAL 90  DAY THEN 1 END) / COUNT(*), 2) AS returned_90d_pct,
       ROUND(100.0 * COUNT(CASE WHEN l.second_order_date <= f.first_order_date + INTERVAL 180 DAY THEN 1 END) / COUNT(*), 2) AS returned_180d_pct
FROM firsts f
LEFT JOIN later l ON f.customer_unique_id = l.customer_unique_id
WHERE f.cohort_month <= '2018-02-01'     -- only cohorts with 6 full months of follow-up
GROUP BY f.cohort_month
ORDER BY f.cohort_month;

-- Q6: Do late deliveries hurt review scores?
SELECT CASE is_late WHEN 1 THEN 'Late' ELSE 'On time' END AS delivery,
       COUNT(*)                                        AS orders,
       ROUND(AVG(review_score), 2)                     AS avg_review,
       ROUND(100.0 * AVG(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END), 1) AS bad_review_pct
FROM fact_orders
WHERE is_delivered = 1 AND review_score IS NOT NULL
GROUP BY 1
ORDER BY 1;

-- Q7: Review score by how late the order was
SELECT CASE
         WHEN delivered_date <= estimated_date            THEN '1. On time / early'
         WHEN delivered_date <= estimated_date + 3        THEN '2. 1-3 days late'
         WHEN delivered_date <= estimated_date + 7        THEN '3. 4-7 days late'
         ELSE '4. 8+ days late' END                       AS lateness,
       COUNT(*)                                           AS orders,
       ROUND(AVG(review_score), 2)                        AS avg_review
FROM fact_orders
WHERE is_delivered = 1 AND review_score IS NOT NULL
GROUP BY 1
ORDER BY 1;

-- Q8: Revenue, delivery time and late % by customer state (top 10 by revenue)
SELECT c.state,
       COUNT(*)                                          AS orders,
       ROUND(SUM(o.product_revenue + o.freight_revenue), 0) AS revenue,
       ROUND(AVG(o.delivery_days), 1)                    AS avg_delivery_days,
       ROUND(100.0 * AVG(o.is_late), 1)                  AS late_pct,
       ROUND(AVG(o.freight_revenue), 2)                  AS avg_freight
FROM fact_orders o
JOIN dim_customers c ON o.customer_unique_id = c.customer_unique_id
WHERE o.is_delivered = 1
GROUP BY c.state
ORDER BY revenue DESC
LIMIT 10;

-- Q9: Payment methods - share of orders and average order value
SELECT payment_type,
       COUNT(*)                                          AS orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS order_share_pct,
       ROUND(AVG(payment_value), 2)                      AS avg_payment,
       ROUND(AVG(installments), 1)                       AS avg_installments
FROM fact_orders
WHERE is_delivered = 1 AND payment_type IS NOT NULL
GROUP BY payment_type
ORDER BY orders DESC;

-- Q10: Seller concentration - how much revenue do the top 10% of sellers bring in?
WITH s AS (
    SELECT seller_id, SUM(price + freight_value) AS revenue
    FROM fact_order_items
    WHERE is_delivered = 1
    GROUP BY seller_id
),
ranked AS (
    SELECT *, NTILE(10) OVER (ORDER BY revenue DESC) AS decile FROM s
)
SELECT decile                                            AS seller_decile,
       COUNT(*)                                          AS sellers,
       ROUND(SUM(revenue), 0)                            AS revenue,
       ROUND(100.0 * SUM(revenue) / SUM(SUM(revenue)) OVER (), 1) AS revenue_share_pct
FROM ranked
GROUP BY decile
ORDER BY decile;

-- 1. Create the schemas if needed
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS analytics;

-- 2. Create staging table if needed
CREATE TABLE IF NOT EXISTS staging.superstore_sales_raw (
    row_id_text text,
    order_id text,
    order_date_text text,
    ship_date_text text,
    ship_mode text,
    customer_id text,
    customer_name text,
    segment text,
    country text,
    city text,
    state text,
    postal_code_text text,
    region text,
    product_id text,
    category text,
    sub_category text,
    product_name text,
    sales_text text,
    quantity_text text,
    discount_text text,
    profit_text text,
    profit_margin_text text,
    order_year_text text,
    order_month_text text,
    year_month_text text,
    discount_band_text text
);

-- 3. Create the analytics table if needed
CREATE TABLE IF NOT EXISTS analytics.sales_order_lines (
    row_id integer PRIMARY KEY,
    order_id text,
    order_date date,
    ship_date date,
    ship_mode text,
    customer_id text,
    customer_name text,
    segment text,
    country text,
    city text,
    state text,
    postal_code text,
    region text,
    product_id text,
    category text,
    sub_category text,
    product_name text,
    sales numeric(12,2),
    quantity integer,
    discount numeric(8,4),
    profit numeric(12,2),
    profit_margin numeric(12,6),
    order_year integer,
    order_month integer,
    year_month date,
    discount_band text
);

-- Add calculated columns if the table already existed without them.
ALTER TABLE analytics.sales_order_lines
    ADD COLUMN IF NOT EXISTS profit_margin numeric(12,6),
    ADD COLUMN IF NOT EXISTS order_year integer,
    ADD COLUMN IF NOT EXISTS order_month integer,
    ADD COLUMN IF NOT EXISTS year_month date,
    ADD COLUMN IF NOT EXISTS discount_band text;

-- 4. Check that the CSV data is in staging before loading it.
SELECT COUNT(*) AS staging_rows
FROM staging.superstore_sales_raw;

-- 5. Clear the old analytics rows so rerunning this script
DELETE FROM analytics.sales_order_lines;

-- 6. Copy and clean the original fields into the analytics table.
INSERT INTO analytics.sales_order_lines (
    row_id,
    order_id,
    order_date,
    ship_date,
    ship_mode,
    customer_id,
    customer_name,
    segment,
    country,
    city,
    state,
    postal_code,
    region,
    product_id,
    category,
    sub_category,
    product_name,
    sales,
    quantity,
    discount,
    profit
)
SELECT
    REPLACE(TRIM(row_id_text), ',', '')::integer,
    order_id,
    TO_DATE(TRIM(order_date_text), 'MM/DD/YYYY'),
    TO_DATE(TRIM(ship_date_text), 'MM/DD/YYYY'),
    ship_mode,
    customer_id,
    customer_name,
    segment,
    country,
    city,
    state,
    REPLACE(TRIM(postal_code_text), ',', ''),
    region,
    product_id,
    category,
    sub_category,
    product_name,
    REPLACE(REPLACE(TRIM(sales_text), '$', ''), ',', '')::numeric,
    REPLACE(TRIM(quantity_text), ',', '')::integer,
    REPLACE(TRIM(discount_text), '%', '')::numeric / 100,
    REPLACE(REPLACE(TRIM(profit_text), '$', ''), ',', '')::numeric
FROM staging.superstore_sales_raw;

-- 7. Calculate the extra analysis fields.
UPDATE analytics.sales_order_lines
SET
    profit_margin = CASE
        WHEN sales = 0 THEN NULL
        ELSE profit / sales
    END,
    order_year = EXTRACT(YEAR FROM order_date)::integer,
    order_month = EXTRACT(MONTH FROM order_date)::integer,
    year_month = DATE_TRUNC('month', order_date)::date,
    discount_band = CASE
        WHEN discount = 0 THEN 'No Discount'
        WHEN discount <= 0.10 THEN '0-10%'
        WHEN discount <= 0.20 THEN '11-20%'
        WHEN discount <= 0.30 THEN '21-30%'
        ELSE '30%+'
    END;

-- 8. Check the final row count and main totals.
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT row_id) AS unique_row_ids,
    COUNT(DISTINCT order_id) AS distinct_orders,
    SUM(sales) AS total_sales,
    SUM(profit) AS total_profit,
    MIN(order_date) AS first_order_date,
    MAX(order_date) AS last_order_date
FROM analytics.sales_order_lines;

-- 9. Check for duplicate row IDs.
SELECT row_id, COUNT(*) AS copies
FROM analytics.sales_order_lines
GROUP BY row_id
HAVING COUNT(*) > 1;

-- 10. Check for shipments before the order date.
SELECT COUNT(*) AS ships_before_order
FROM analytics.sales_order_lines
WHERE ship_date < order_date;

-- 11. Check for discounts outside the 0-to-1 range.
SELECT COUNT(*) AS invalid_discounts
FROM analytics.sales_order_lines
WHERE discount < 0 OR discount > 1;

-- 12. Sales and profit by month.
SELECT
    year_month,
    SUM(sales) AS total_sales,
    SUM(profit) AS total_profit,
    COUNT(DISTINCT order_id) AS distinct_orders
FROM analytics.sales_order_lines
GROUP BY year_month
ORDER BY year_month;

-- 13. Sales and profit by region.
SELECT
    region,
    SUM(sales) AS total_sales,
    SUM(profit) AS total_profit
FROM analytics.sales_order_lines
GROUP BY region
ORDER BY total_sales DESC;

-- 14. Sales and profit by category and sub-category.
SELECT
    category,
    sub_category,
    SUM(sales) AS total_sales,
    SUM(profit) AS total_profit
FROM analytics.sales_order_lines
GROUP BY category, sub_category
ORDER BY total_profit DESC;

-- 15. Sales and profit by customer segment.
SELECT
    segment,
    SUM(sales) AS total_sales,
    SUM(profit) AS total_profit,
    COUNT(DISTINCT order_id) AS distinct_orders
FROM analytics.sales_order_lines
GROUP BY segment
ORDER BY total_sales DESC;

-- 16. Top 10 products by profit.
SELECT
    product_name,
    SUM(sales) AS total_sales,
    SUM(profit) AS total_profit
FROM analytics.sales_order_lines
GROUP BY product_name
ORDER BY total_profit DESC
LIMIT 10;
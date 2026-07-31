-- ============================================================
-- Northwind Business Analytics — SQL Data Cleaning, EDA & Insights
-- Database: SQLite (northwind.db)
-- ============================================================

-- ============================================================
-- SECTION 1: DATA CLEANING / QUALITY CHECKS
-- ============================================================

-- 1.1 Check for orphaned foreign keys (orders with no matching customer)
SELECT COUNT(*) AS orphan_orders
FROM Orders o
LEFT JOIN Customers c ON o.CustomerID = c.CustomerID
WHERE c.CustomerID IS NULL;

-- 1.2 Check for order details referencing non-existent products
SELECT COUNT(*) AS orphan_order_details
FROM "Order Details" od
LEFT JOIN Products p ON od.ProductID = p.ProductID
WHERE p.ProductID IS NULL;

-- 1.3 Check for invalid quantity/price values (data entry errors)
SELECT COUNT(*) AS bad_line_items
FROM "Order Details"
WHERE Quantity <= 0 OR UnitPrice <= 0 OR Discount < 0 OR Discount > 1;

-- 1.4 Orders that were never shipped (open/lost orders)
SELECT COUNT(*) AS unshipped_orders
FROM Orders
WHERE ShippedDate IS NULL;

-- 1.5 Orders shipped before they were placed (data errors)
SELECT COUNT(*) AS impossible_shipping_dates
FROM Orders
WHERE ShippedDate IS NOT NULL AND ShippedDate < OrderDate;

-- 1.6 Duplicate customers by company name (case-insensitive)
SELECT LOWER(CompanyName) AS company_lower, COUNT(*) AS cnt
FROM Customers
GROUP BY LOWER(CompanyName)
HAVING COUNT(*) > 1;

-- 1.7 Products with negative or missing unit price
SELECT COUNT(*) AS bad_products
FROM Products
WHERE UnitPrice IS NULL OR UnitPrice < 0;


-- ============================================================
-- SECTION 2: EXPLORATORY DATA ANALYSIS
-- ============================================================

-- 2.1 Overall business size
SELECT
    COUNT(DISTINCT o.OrderID)      AS total_orders,
    COUNT(DISTINCT o.CustomerID)   AS unique_customers,
    ROUND(SUM(od.UnitPrice * od.Quantity * (1 - od.Discount)), 2) AS total_revenue
FROM Orders o
JOIN "Order Details" od ON o.OrderID = od.OrderID;

-- 2.2 Revenue by year
SELECT
    strftime('%Y', o.OrderDate) AS order_year,
    ROUND(SUM(od.UnitPrice * od.Quantity * (1 - od.Discount)), 2) AS revenue,
    COUNT(DISTINCT o.OrderID) AS orders
FROM Orders o
JOIN "Order Details" od ON o.OrderID = od.OrderID
GROUP BY order_year
ORDER BY order_year;

-- 2.3 Revenue by product category
SELECT
    c.CategoryName,
    ROUND(SUM(od.UnitPrice * od.Quantity * (1 - od.Discount)), 2) AS revenue,
    COUNT(DISTINCT od.OrderID) AS orders_containing_category
FROM "Order Details" od
JOIN Products p ON od.ProductID = p.ProductID
JOIN Categories c ON p.CategoryID = c.CategoryID
GROUP BY c.CategoryName
ORDER BY revenue DESC;

-- 2.4 Average order fulfillment time (days), excluding unshipped orders
SELECT
    ROUND(AVG(julianday(ShippedDate) - julianday(OrderDate)), 2) AS avg_fulfillment_days,
    ROUND(MIN(julianday(ShippedDate) - julianday(OrderDate)), 2) AS min_days,
    ROUND(MAX(julianday(ShippedDate) - julianday(OrderDate)), 2) AS max_days
FROM Orders
WHERE ShippedDate IS NOT NULL;

-- 2.5 Late shipments: shipped after the RequiredDate promised to the customer
SELECT
    COUNT(*) AS late_orders,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM Orders WHERE ShippedDate IS NOT NULL), 2) AS pct_late
FROM Orders
WHERE ShippedDate IS NOT NULL AND ShippedDate > RequiredDate;


-- ============================================================
-- SECTION 3: BUSINESS INSIGHTS (window functions, CTEs)
-- ============================================================

-- 3.1 Top 10 products by revenue
SELECT
    p.ProductName,
    ROUND(SUM(od.UnitPrice * od.Quantity * (1 - od.Discount)), 2) AS revenue,
    SUM(od.Quantity) AS units_sold
FROM "Order Details" od
JOIN Products p ON od.ProductID = p.ProductID
GROUP BY p.ProductName
ORDER BY revenue DESC
LIMIT 10;

-- 3.2 Top 10 customers by lifetime revenue, with rank
WITH customer_revenue AS (
    SELECT
        c.CustomerID,
        c.CompanyName,
        SUM(od.UnitPrice * od.Quantity * (1 - od.Discount)) AS revenue
    FROM Customers c
    JOIN Orders o ON c.CustomerID = o.CustomerID
    JOIN "Order Details" od ON o.OrderID = od.OrderID
    GROUP BY c.CustomerID, c.CompanyName
)
SELECT
    CompanyName,
    ROUND(revenue, 2) AS revenue,
    RANK() OVER (ORDER BY revenue DESC) AS revenue_rank
FROM customer_revenue
ORDER BY revenue DESC
LIMIT 10;

-- 3.3 Employee sales performance leaderboard
WITH employee_sales AS (
    SELECT
        e.EmployeeID,
        e.FirstName || ' ' || e.LastName AS employee_name,
        SUM(od.UnitPrice * od.Quantity * (1 - od.Discount)) AS revenue,
        COUNT(DISTINCT o.OrderID) AS orders_handled
    FROM Employees e
    JOIN Orders o ON e.EmployeeID = o.EmployeeID
    JOIN "Order Details" od ON o.OrderID = od.OrderID
    GROUP BY e.EmployeeID
)
SELECT
    employee_name,
    ROUND(revenue, 2) AS revenue,
    orders_handled,
    ROUND(revenue / orders_handled, 2) AS avg_revenue_per_order,
    RANK() OVER (ORDER BY revenue DESC) AS rank
FROM employee_sales
ORDER BY revenue DESC;

-- 3.4 Month-over-month revenue growth (window function LAG)
WITH monthly_revenue AS (
    SELECT
        strftime('%Y-%m', o.OrderDate) AS ym,
        SUM(od.UnitPrice * od.Quantity * (1 - od.Discount)) AS revenue
    FROM Orders o
    JOIN "Order Details" od ON o.OrderID = od.OrderID
    GROUP BY ym
)
SELECT
    ym,
    ROUND(revenue, 2) AS revenue,
    ROUND(revenue - LAG(revenue) OVER (ORDER BY ym), 2) AS mom_change,
    ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY ym)) / LAG(revenue) OVER (ORDER BY ym), 2) AS mom_pct_change
FROM monthly_revenue
ORDER BY ym;

-- 3.5 Discount impact: revenue and average discount by category
SELECT
    c.CategoryName,
    ROUND(AVG(od.Discount) * 100, 2) AS avg_discount_pct,
    ROUND(SUM(od.UnitPrice * od.Quantity * od.Discount), 2) AS total_discount_given,
    ROUND(SUM(od.UnitPrice * od.Quantity * (1 - od.Discount)), 2) AS net_revenue
FROM "Order Details" od
JOIN Products p ON od.ProductID = p.ProductID
JOIN Categories c ON p.CategoryID = c.CategoryID
GROUP BY c.CategoryName
ORDER BY total_discount_given DESC;

-- 3.6 Customers who haven't ordered in 60+ days (churn risk)
-- Note: average gap between a customer's orders in this dataset is ~27 days,
-- so a 60-day cutoff is the meaningful "at risk" threshold here, not the usual 365.
WITH last_order AS (
    SELECT CustomerID, MAX(OrderDate) AS last_order_date
    FROM Orders
    GROUP BY CustomerID
),
max_date AS (
    SELECT MAX(OrderDate) AS latest FROM Orders
)
SELECT
    c.CompanyName,
    lo.last_order_date,
    CAST(julianday((SELECT latest FROM max_date)) - julianday(lo.last_order_date) AS INTEGER) AS days_since_last_order
FROM last_order lo
JOIN Customers c ON lo.CustomerID = c.CustomerID
WHERE julianday((SELECT latest FROM max_date)) - julianday(lo.last_order_date) > 60
ORDER BY days_since_last_order DESC
LIMIT 15;

-- 3.7 Products at risk of stockout (below reorder level, still active)
SELECT
    ProductName,
    UnitsInStock,
    ReorderLevel,
    UnitsOnOrder
FROM Products
WHERE UnitsInStock <= ReorderLevel AND Discontinued = 0
ORDER BY UnitsInStock ASC;

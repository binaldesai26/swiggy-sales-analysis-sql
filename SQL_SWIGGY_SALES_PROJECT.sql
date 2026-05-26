-- ============================================================
-- PROJECT   : Swiggy Sales Analysis
-- PLATFORM  : SQL Server
-- DESCRIPTION: End-to-end pipeline covering data validation,
--              star schema modelling, and business KPIs for
--              Swiggy food delivery data across Indian cities.
-- SECTIONS  :
--   1. Data Validation & Cleaning
--   2. Star Schema (Dimension + Fact Tables)
--   3. Data Load (Dimensions → Fact)
--   4. KPIs
--   5. Deep-Dive Business Analysis
-- ============================================================


-- ============================================================
-- SECTION 1 : DATA VALIDATION & CLEANING
-- ============================================================

-- 1.1  NULL CHECK
-- Counts missing values in every business-critical column.

SELECT
    SUM(CASE WHEN STATE           IS NULL THEN 1 ELSE 0 END) AS State_Null,
    SUM(CASE WHEN CITY            IS NULL THEN 1 ELSE 0 END) AS City_Null,
    SUM(CASE WHEN ORDER_DATE      IS NULL THEN 1 ELSE 0 END) AS Order_Date_Null,
    SUM(CASE WHEN RESTAURANT_NAME IS NULL THEN 1 ELSE 0 END) AS Restaurant_Name_Null,
    SUM(CASE WHEN LOCATION        IS NULL THEN 1 ELSE 0 END) AS Location_Null,
    SUM(CASE WHEN CATEGORY        IS NULL THEN 1 ELSE 0 END) AS Category_Null,
    SUM(CASE WHEN DISH_NAME       IS NULL THEN 1 ELSE 0 END) AS Dish_Name_Null,
    SUM(CASE WHEN PRICE_INR       IS NULL THEN 1 ELSE 0 END) AS Price_INR_Null,
    SUM(CASE WHEN RATING          IS NULL THEN 1 ELSE 0 END) AS Rating_Null,
    SUM(CASE WHEN RATING_COUNT    IS NULL THEN 1 ELSE 0 END) AS Rating_Count_Null
FROM swiggy_data;


-- 1.2  BLANK / EMPTY STRING CHECK
-- Detects rows with empty strings that could corrupt aggregations.

SELECT *
FROM swiggy_data
WHERE
    STATE           = '' OR
    CITY            = '' OR
    ORDER_DATE      = '' OR
    RESTAURANT_NAME = '' OR
    LOCATION        = '' OR
    CATEGORY        = '' OR
    DISH_NAME       = '';


-- 1.3  DUPLICATE DETECTION
-- Identifies exact duplicate rows across all business columns.

SELECT
    STATE, CITY, ORDER_DATE, RESTAURANT_NAME, LOCATION,
    CATEGORY, DISH_NAME, PRICE_INR, RATING, RATING_COUNT,
    COUNT(*) AS Duplicate_Count
FROM swiggy_data
GROUP BY
    STATE, CITY, ORDER_DATE, RESTAURANT_NAME, LOCATION,
    CATEGORY, DISH_NAME, PRICE_INR, RATING, RATING_COUNT
HAVING COUNT(*) > 1;


-- 1.4  DUPLICATE REMOVAL
-- Retains one record per unique combination using ROW_NUMBER().

WITH CTE AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY STATE, CITY, ORDER_DATE, RESTAURANT_NAME, LOCATION,
                         CATEGORY, DISH_NAME, PRICE_INR, RATING, RATING_COUNT
            ORDER BY (SELECT NULL)
        ) AS RN
    FROM swiggy_data
)
DELETE FROM CTE WHERE RN > 1;


-- ============================================================
-- SECTION 2 : STAR SCHEMA — DIMENSION & FACT TABLES
-- ============================================================

-- 2.1  dim_date

CREATE TABLE dim_date (
    date_id    INT          IDENTITY(1,1) PRIMARY KEY,
    Full_Date  DATE,
    Year       INT,
    Month      INT,
    Month_Name VARCHAR(20),
    Quarter    INT,
    Week       INT,
    Day        INT
);


-- 2.2  dim_location

CREATE TABLE dim_location (
    location_id INT          IDENTITY(1,1) PRIMARY KEY,
    State       VARCHAR(100),
    City        VARCHAR(100),
    Location    VARCHAR(200)
);


-- 2.3  dim_restaurant

CREATE TABLE dim_restaurant (
    restaurant_id   INT          IDENTITY(1,1) PRIMARY KEY,
    Restaurant_Name VARCHAR(200)
);


-- 2.4  dim_category

CREATE TABLE dim_category (
    category_id INT          IDENTITY(1,1) PRIMARY KEY,
    Category    VARCHAR(200)
);


-- 2.5  dim_dish

CREATE TABLE dim_dish (
    dish_id   INT          IDENTITY(1,1) PRIMARY KEY,
    Dish_Name VARCHAR(500)
);


-- 2.6  fact_swiggy_orders (central fact table)

CREATE TABLE fact_swiggy_orders (
    order_id      INT            IDENTITY(1,1) PRIMARY KEY,
    date_id       INT,
    location_id   INT,
    restaurant_id INT,
    category_id   INT,
    dish_id       INT,
    Price_INR     DECIMAL(10,2),
    Rating        DECIMAL(4,2),
    Rating_Count  INT,

    FOREIGN KEY (date_id)       REFERENCES dim_date(date_id),
    FOREIGN KEY (location_id)   REFERENCES dim_location(location_id),
    FOREIGN KEY (restaurant_id) REFERENCES dim_restaurant(restaurant_id),
    FOREIGN KEY (category_id)   REFERENCES dim_category(category_id),
    FOREIGN KEY (dish_id)       REFERENCES dim_dish(dish_id)
);


-- ============================================================
-- SECTION 3 : DATA LOAD — DIMENSIONS THEN FACT
-- ============================================================

-- 3.1  Load dim_date

INSERT INTO dim_date (Full_Date, Year, Month, Month_Name, Quarter, Week, Day)
SELECT DISTINCT
    Order_Date,
    YEAR(Order_Date),
    MONTH(Order_Date),
    DATENAME(MONTH, Order_Date),
    DATEPART(QUARTER, Order_Date),
    DATEPART(WEEK, Order_Date),
    DAY(Order_Date)
FROM swiggy_data
WHERE Order_Date IS NOT NULL;


-- 3.2  Load dim_location

INSERT INTO dim_location (State, City, Location)
SELECT DISTINCT State, City, Location
FROM swiggy_data;


-- 3.3  Load dim_restaurant

INSERT INTO dim_restaurant (Restaurant_Name)
SELECT DISTINCT Restaurant_Name
FROM swiggy_data;


-- 3.4  Load dim_category

INSERT INTO dim_category (Category)
SELECT DISTINCT Category
FROM swiggy_data;


-- 3.5  Load dim_dish

INSERT INTO dim_dish (Dish_Name)
SELECT DISTINCT Dish_Name
FROM swiggy_data;


-- 3.6  Load fact_swiggy_orders
-- Resolves all surrogate keys via JOINs on dimension tables.

INSERT INTO fact_swiggy_orders (
    date_id, location_id, restaurant_id, category_id, dish_id,
    Price_INR, Rating, Rating_Count
)
SELECT
    DD.date_id,
    DL.location_id,
    DR.restaurant_id,
    DC.category_id,
    DI.dish_id,
    S.Price_INR,
    S.Rating,
    S.Rating_Count
FROM swiggy_data S
JOIN dim_date       DD ON DD.Full_Date       = S.Order_Date
JOIN dim_location   DL ON DL.State           = S.State
                      AND DL.City            = S.City
                      AND DL.Location        = S.Location
JOIN dim_restaurant DR ON DR.Restaurant_Name = S.Restaurant_Name
JOIN dim_category   DC ON DC.Category        = S.Category
JOIN dim_dish       DI ON DI.Dish_Name       = S.Dish_Name;


-- ============================================================
-- SECTION 4 : KPIs
-- ============================================================

-- 4.1  Total Orders

SELECT COUNT(*) AS Total_Orders
FROM fact_swiggy_orders;


-- 4.2  Total Revenue (INR Million)

SELECT
    CAST(ROUND(SUM(Price_INR) / 1000000.0, 2) AS DECIMAL(10,2))
    AS Total_Revenue_INR_Million
FROM fact_swiggy_orders;


-- 4.3  Average Dish Price (INR)

SELECT
    CAST(ROUND(AVG(Price_INR), 2) AS DECIMAL(10,2)) AS Avg_Dish_Price_INR
FROM fact_swiggy_orders;


-- 4.4  Average Rating

SELECT
    CAST(ROUND(AVG(Rating), 2) AS DECIMAL(10,2)) AS Avg_Rating
FROM fact_swiggy_orders;


-- ============================================================
-- SECTION 5 : DEEP-DIVE BUSINESS ANALYSIS
-- ============================================================

-- ── 5A : DATE-BASED ANALYSIS ─────────────────────────────────

-- 5A.1  Monthly Order Trends

SELECT
    D.Year,
    D.Month,
    D.Month_Name,
    COUNT(*) AS Total_Orders
FROM fact_swiggy_orders F
JOIN dim_date D ON F.date_id = D.date_id
GROUP BY D.Year, D.Month, D.Month_Name
ORDER BY D.Year, D.Month;


-- 5A.2  Monthly Revenue Trends (in Lakhs)

SELECT
    D.Year,
    D.Month,
    D.Month_Name,
    CAST(SUM(F.Price_INR) / 100000.0 AS DECIMAL(10,2)) AS Revenue_Lakhs
FROM fact_swiggy_orders F
JOIN dim_date D ON F.date_id = D.date_id
GROUP BY D.Year, D.Month, D.Month_Name
ORDER BY D.Year, D.Month;


-- 5A.3  Quarterly Order Trends

SELECT
    D.Year,
    D.Quarter,
    COUNT(*) AS Total_Orders
FROM fact_swiggy_orders F
JOIN dim_date D ON F.date_id = D.date_id
GROUP BY D.Year, D.Quarter
ORDER BY D.Year, D.Quarter;


-- 5A.4  Quarterly Revenue Trends (in Lakhs)

SELECT
    D.Year,
    D.Quarter,
    CAST(SUM(F.Price_INR) / 100000.0 AS DECIMAL(10,2)) AS Revenue_Lakhs
FROM fact_swiggy_orders F
JOIN dim_date D ON F.date_id = D.date_id
GROUP BY D.Year, D.Quarter
ORDER BY D.Year, D.Quarter;


-- 5A.5  Yearly Order Trends

SELECT
    D.Year,
    COUNT(*) AS Total_Orders
FROM fact_swiggy_orders F
JOIN dim_date D ON F.date_id = D.date_id
GROUP BY D.Year
ORDER BY D.Year;


-- 5A.6  Day-of-Week Order Patterns

SELECT
    D.Year,
    DATENAME(WEEKDAY, D.Full_Date)   AS Day_Of_Week,
    COUNT(*)                         AS Total_Orders
FROM fact_swiggy_orders F
JOIN dim_date D ON F.date_id = D.date_id
GROUP BY D.Year, DATENAME(WEEKDAY, D.Full_Date), DATEPART(WEEKDAY, D.Full_Date)
ORDER BY D.Year, DATEPART(WEEKDAY, D.Full_Date);


-- ── 5B : LOCATION-BASED ANALYSIS ────────────────────────────

-- 5B.1  Top 10 Cities by Order Volume

SELECT TOP 10
    L.City,
    COUNT(*) AS Total_Orders
FROM fact_swiggy_orders F
JOIN dim_location L ON F.location_id = L.location_id
GROUP BY L.City
ORDER BY Total_Orders DESC;


-- 5B.2  Revenue Contribution by State (in Lakhs)

SELECT
    L.State,
    CAST(SUM(F.Price_INR) / 100000.0 AS DECIMAL(10,2)) AS Revenue_Lakhs
FROM fact_swiggy_orders F
JOIN dim_location L ON F.location_id = L.location_id
GROUP BY L.State
ORDER BY SUM(F.Price_INR) DESC;


-- ── 5C : RESTAURANT & FOOD PERFORMANCE ───────────────────────

-- 5C.1  Top 10 Restaurants by Order Volume

SELECT TOP 10
    R.Restaurant_Name,
    COUNT(*) AS Total_Orders
FROM fact_swiggy_orders F
JOIN dim_restaurant R ON F.restaurant_id = R.restaurant_id
GROUP BY R.Restaurant_Name
ORDER BY Total_Orders DESC;


-- 5C.2  Top 10 Restaurants by Revenue (INR)

SELECT TOP 10
    R.Restaurant_Name,
    SUM(F.Price_INR) AS Total_Revenue_INR
FROM fact_swiggy_orders F
JOIN dim_restaurant R ON F.restaurant_id = R.restaurant_id
GROUP BY R.Restaurant_Name
ORDER BY Total_Revenue_INR DESC;


-- 5C.3  Top 10 Categories by Order Volume

SELECT TOP 10
    C.Category,
    COUNT(*) AS Total_Orders
FROM fact_swiggy_orders F
JOIN dim_category C ON F.category_id = C.category_id
GROUP BY C.Category
ORDER BY Total_Orders DESC;


-- 5C.4  Top 10 Most Ordered Dishes

SELECT TOP 10
    DI.Dish_Name,
    COUNT(*) AS Total_Orders
FROM fact_swiggy_orders F
JOIN dim_dish DI ON F.dish_id = DI.dish_id
GROUP BY DI.Dish_Name
ORDER BY Total_Orders DESC;


-- 5C.5  Cuisine Performance — Orders & Average Rating

SELECT
    C.Category,
    COUNT(*)                                    AS Total_Orders,
    CAST(AVG(F.Rating) AS DECIMAL(10,2))        AS Avg_Rating
FROM fact_swiggy_orders F
JOIN dim_category C ON F.category_id = C.category_id
GROUP BY C.Category
ORDER BY Total_Orders DESC;


-- ── 5D : CUSTOMER SPENDING INSIGHTS ─────────────────────────

-- 5D.1  Order Distribution by Price Range

SELECT
    CASE
        WHEN Price_INR <  100                  THEN 'Under 100'
        WHEN Price_INR BETWEEN 100 AND 199     THEN '100 - 199'
        WHEN Price_INR BETWEEN 200 AND 299     THEN '200 - 299'
        WHEN Price_INR BETWEEN 300 AND 499     THEN '300 - 499'
        ELSE '500+'
    END                     AS Price_Range,
    COUNT(*)                AS Total_Orders
FROM fact_swiggy_orders
GROUP BY
    CASE
        WHEN Price_INR <  100                  THEN 'Under 100'
        WHEN Price_INR BETWEEN 100 AND 199     THEN '100 - 199'
        WHEN Price_INR BETWEEN 200 AND 299     THEN '200 - 299'
        WHEN Price_INR BETWEEN 300 AND 499     THEN '300 - 499'
        ELSE '500+'
    END
ORDER BY Total_Orders DESC;


-- ── 5E : RATINGS ANALYSIS ────────────────────────────────────

-- 5E.1  Rating Distribution (1–5)

SELECT
    Rating,
    COUNT(*) AS Total_Orders
FROM fact_swiggy_orders
GROUP BY Rating
ORDER BY Rating DESC;
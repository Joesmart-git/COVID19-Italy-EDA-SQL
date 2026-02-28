/*
===============================================================================
Project: Operation Ground Zero - COVID-19 Data Exploration
Author: Joesmart V. Apan
Tool: Google BigQuery (Standard SQL)
Description: Exploratory Data Analysis (EDA) of Italy's national, regional, 
and provincial epidemiological data to identify peak infection periods and 
localized surge drivers.
===============================================================================
*/

-- ============================================================================
-- Phase 1: National Overview (EDA & Time-Series)
-- The Goal: Identify the top 3 absolute worst months of the pandemic.
-- ============================================================================

SELECT
  DATE(DATE_TRUNC(N.date, MONTH)) AS month
  , SUM(N.new_total_confirmed_cases) AS total_cases
FROM `dabc21.covid19_italy.national_trends` AS N
GROUP BY
  month
ORDER BY
  total_cases DESC
LIMIT 3
;


-- ============================================================================
-- Phase 2: Regional Testing Efficiency (Relational JOINs)
-- The Goal: Evaluate regional testing contributions during the absolute peaks.
-- ============================================================================

SELECT
  DATE(R.date) AS day
  , R.region_name
  , R.tests_performed AS reg_test
  , N.tests_performed AS nat_test
  , ROUND((R.tests_performed / N.tests_performed)*100,4) AS R_pct_contri
FROM `dabc21.covid19_italy.data_by_region` AS R
INNER JOIN `dabc21.covid19_italy.national_trends` AS N
  ON DATE(R.date) = DATE(N.date)
WHERE
  EXTRACT(YEAR FROM R.date) = 2022 AND EXTRACT(MONTH from R.date) IN (1,3,7) -- Dynamic filtering based on Phase 1 peak results
  AND N.tests_performed > 0 -- Defensive coding: prevents division-by-zero fatal errors
ORDER BY
  day ASC
;


-- ============================================================================
-- Phase 3: Deriving Metrics (Window Functions)
-- The Goal: Derive net-new weekly cases from running cumulative totals.
-- ============================================================================

WITH weekly_record AS ( --Establish clean weekly baselines to avoid daily reporting noise
  SELECT
    DATE(DATE_TRUNC(P.date, WEEK)) AS week
    , P.province_name AS prov_name
    , MAX(P.confirmed_cases) AS weekly_total_cases
  FROM  `dabc21.covid19_italy.data_by_province` AS P
  GROUP BY
    week
    , P.province_name
)

SELECT
  week
  , prov_name
  , weekly_total_cases
  , weekly_total_cases - LAG(weekly_total_cases) OVER ( -- subtract the previous week's cumulative total to derive net-new cases
      PARTITION BY  W.prov_name
      ORDER BY week ASC
    ) AS weekly_increase
FROM weekly_record AS W
ORDER BY
  prov_name
  , week ASC
;


-- ============================================================================
-- Phase 4: The "Ground Zero" Report (CTEs & Scalar Subqueries)
-- The Goal: Calculate hierarchical percentage contributions for the worst day.
-- ============================================================================

WITH new_table AS (
  SELECT
    DATE(P.date) AS day
    , P.province_name AS province_name
    , R.region_name AS region_name
    , P.confirmed_cases AS prov_cases
    , R.total_confirmed_cases AS reg_cases
    , N.total_confirmed_cases AS nat_cases
  FROM `dabc21.covid19_italy.data_by_province` AS P
  INNER JOIN `dabc21.covid19_italy.data_by_region` AS R
    ON P.date = R.date
    AND P.region_code = R.region_code
  LEFT JOIN `dabc21.covid19_italy.national_trends` AS N
    ON P.date = N.date
)

SELECT
  NT.day
  , NT.province_name
  , NT.region_name 
  , NT.prov_cases
  , NT.nat_cases
  , NT.reg_cases
  , ROUND((SUM(NT.prov_cases)/NT.reg_cases)*100,4) AS prov_contri_to_reg
  , ROUND((SUM(NT.prov_cases)/NT.nat_cases)*100,4) AS prov_contri_to_nat
  , ROUND((SUM(NT.reg_cases)/ NT.nat_cases)*100,4) AS reg_contri_to_nat
FROM new_table AS NT
WHERE
	-- Dynamically fetches the peak infection day
  NT.day = 
  (SELECT DATE(N1.date) AS worst_day        
  FROM `dabc21.covid19_italy.national_trends` AS N1
  ORDER BY N1.new_total_confirmed_cases DESC
  LIMIT 1)
GROUP BY
  NT.day
  , NT.province_name
  , NT.prov_cases
  , NT.region_name
  , NT.nat_cases
  , NT.reg_cases
ORDER BY
  NT. prov_cases DESC
-- Isolating the top 5 primary drivers of the national surge
LIMIT 
  5
;

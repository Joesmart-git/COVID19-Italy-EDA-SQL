# 🦠 Operation Ground Zero: COVID-19 Public Health EDA

![Google BigQuery](https://img.shields.io/badge/Google_BigQuery-669DF6?style=for-the-badge&logo=google-cloud&logoColor=white)
![SQL](https://img.shields.io/badge/Standard_SQL-4479A1?style=for-the-badge&logo=mysql&logoColor=white)

📖 **[Read the Full Interactive Case Study on My Notion Portfolio](https://whispering-crater-183.notion.site/Project-Operation-Ground-Zero-COVID-19-Data-Exploration-314e54702f0b808ca5e5d3b7f814443b?source=copy_link)**

## 📌 Project Overview & Business Impact
During the height of the COVID-19 pandemic, tracking the spread across different geographical tiers (National, Regional, Provincial) was critical for emergency resource allocation. This project utilizes **Google BigQuery** and **Standard SQL** to conduct an Exploratory Data Analysis (EDA) on Italy's national epidemiological database.

**Business Value Delivered:**
By seamlessly bridging multi-grain hierarchical datasets and deriving hidden metrics via Window Functions, this analytical model empowers stakeholders to bypass high-level national noise. Officials can immediately isolate localized outbreaks, calculate exact proportional impact, and deploy targeted emergency medical resources directly to the specific "Ground Zero" provinces driving the national surges.

<div align="center">
  <img width="1815" height="326" alt="image" src="https://github.com/user-attachments/assets/ca55cd63-a912-46cf-a9c2-f60a41afa447" />
  </div>

## 🛠️ Tools & SQL Skills Demonstrated
* **Tool:** Google BigQuery / Standard SQL
* **Dataset:** Public COVID-19 Dataset (Google BigQuery)
* **Skills:** Common Table Expressions (CTEs), Subqueries, Window Functions (`LAG`), Multi-Table Relational JOINs, Hierarchical Aggregation, Data Derivation (Cumulative to Incremental).

---

## 🧠 Technical Execution & Methodology

### 1. Macro-Timeline Analysis (EDA & Time-Series)
To establish a baseline, I rolled up daily epidemiological records into monthly aggregates to identify the absolute worst months of the pandemic natively.
```sql
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
```
*Result: January, March, and July 2022 were identified as the peak surge periods.*

| month | total_cases |
| :--- | :--- |
| 2022-01-01 | 4,730,380 |
| 2022-07-01 | 2,443,084 |
| 2022-03-01 | 1,832,360 |

### 2. Regional Testing Efficiency
To evaluate localized testing efforts during the absolute peaks, I bridged the Regional and National tables using an `INNER JOIN` and dynamically filtered for the months identified in Phase 1. I engineered mathematical logic to calculate the exact percentage each region contributed to the national testing pool, implementing defensive `> 0` logic to prevent division-by-zero errors.
```sql
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
```
*Result Snapshot: Friuli Venezia Giulia led proportional testing contributions during the January 2022 peak.*

| day | region_name | reg_test | nat_test | R_pct_contri |
| :--- | :--- | :--- | :--- | :--- |
| 2022-01-01 | Friuli Venezia Giulia | 4,551,164 | 141,268,542 | 3.2216 |
| 2022-01-01 | Calabria | 1,678,388 | 141,268,542 | 1.1881 |
| 2022-01-01 | Abruzzo | 3,583,600 | 141,268,542 | 2.5367 |
| 2022-01-01 | P.A. Trento | 1,860,109 | 141,268,542 | 1.3167 |
| 2022-01-01 | P.A. Bolzano | 3,014,323 | 141,268,542 | 2.1338 |

### 3. Data Derivation via Window Functions
The provincial database only tracked infections as a running cumulative total. To find the true weekly spikes, I built a two-step CTE process to extract the `MAX()` cumulative cases per week, and then utilized the `LAG()` window function to dynamically subtract the previous week's total, deriving a clean week-over-week growth metric.
```sql
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
```
*Result Snapshot: Successfully generated net-new weekly cases (`weekly_increase`) from static running totals.*

| week | prov_name | weekly_total_cases | weekly_increase |
| :--- | :--- | :--- | :--- |
| 2020-02-23 | Agrigento | 0 | null |
| 2020-03-01 | Agrigento | 1 | 1 |
| 2020-03-08 | Agrigento | 17 | 16 |
| 2020-03-15 | Agrigento | 36 | 19 |
| 2020-03-22 | Agrigento | 58 | 22 |

### 4. Hierarchical Modeling & The "Ground Zero" Report
To isolate the exact provinces causing the national surges, I engineered a robust Common Table Expression (CTE) that joined all three geographical tiers (Province, Region, National). Using a nested scalar subquery in the `WHERE` clause, the query dynamically targets the single worst day in the country's history. I utilized this unified base table to simultaneously calculate hierarchical percentage contributions (`prov_contri_to_reg` and `prov_contri_to_nat`) in a single, streamlined query execution.
```sql
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
```
<div align="center">
  <img width="1815" height="326" alt="image" src="https://github.com/user-attachments/assets/ca55cd63-a912-46cf-a9c2-f60a41afa447" />
  </div>


## 📂 Repository Structure
* [📁 /01_SQL_Scripts](./01_SQL_Scripts) - Contains the raw `.sql` files for all four phases of the analysis.


---
*If you are a recruiter or hiring manager, please visit the **[Notion Case Study](https://whispering-crater-183.notion.site/Project-Operation-Ground-Zero-COVID-19-Data-Exploration-314e54702f0b808ca5e5d3b7f814443b?source=copy_link)** for a deeper dive into the business context and visual query results.*

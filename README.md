# Northwind Business Analytics — SQL Data Cleaning, EDA & Insights

End-to-end data cleaning, exploratory analysis, and business-insight extraction done **entirely
in SQL** (CTEs, window functions, joins, aggregations) against the classic Northwind relational
database — orders, order line items, products, customers, and employees.

## Why SQL-only (no Python/BI tool)
This project deliberately does the full workflow — quality checks, aggregation, ranking,
trend analysis, cohort-style churn detection — using only SQL, to demonstrate SQL fluency
independent of a scripting language or dashboarding tool.

## Database
`northwind.db` (SQLite) — 16,282 orders, 609,283 order line items, 93 customers, 77 products,
9 employees, 8 categories.

## Schema
The database has 13 tables total; `analysis.sql` queries the 6 below. (Suppliers, Shippers,
Territories, Regions, EmployeeTerritories, and two empty customer-demographics tables exist in
the schema but aren't used in the analysis.)

```mermaid
erDiagram
    CUSTOMERS ||--o{ ORDERS : places
    EMPLOYEES ||--o{ ORDERS : handles
    EMPLOYEES ||--o{ EMPLOYEES : "reports to"
    ORDERS ||--o{ ORDER_DETAILS : contains
    PRODUCTS ||--o{ ORDER_DETAILS : "line item"
    CATEGORIES ||--o{ PRODUCTS : includes

    CUSTOMERS {
        string CustomerID PK
        string CompanyName
        string Country
    }
    ORDERS {
        int OrderID PK
        string CustomerID FK
        int EmployeeID FK
        date OrderDate
        date RequiredDate
        date ShippedDate
    }
    ORDER_DETAILS {
        int OrderID PK,FK
        int ProductID PK,FK
        numeric UnitPrice
        int Quantity
        real Discount
    }
    PRODUCTS {
        int ProductID PK
        string ProductName
        int CategoryID FK
        int UnitsInStock
        int ReorderLevel
    }
    CATEGORIES {
        int CategoryID PK
        string CategoryName
    }
    EMPLOYEES {
        int EmployeeID PK
        int ReportsTo FK
        string FirstName
        string LastName
    }
```

**Legend:** `||--o{` = one-to-many (one row on the `||` side relates to zero-or-more rows on the
`o{` side) — e.g. one `CUSTOMERS` row relates to many `ORDERS` rows. `PK` = primary key,
`FK` = foreign key, `PK,FK` = column is both (a composite key that's also a reference to another
table, as in `ORDER_DETAILS`).

| Table | Rows |
|---|---|
| `Customers` | 93 |
| `Orders` | 16,282 |
| `Order Details` | 609,283 |
| `Products` | 77 |
| `Categories` | 8 |
| `Employees` | 9 |

`"Order Details"` needs double-quoting in SQL since the table name contains a space.

`analysis.sql` also creates one derived object, `OrderLineRevenue` — a view over `Order Details`
that computes `UnitPrice * Quantity * (1 - Discount)` once as `LineRevenue`, so every revenue
query joins against it instead of repeating that formula. It's created with
`CREATE VIEW IF NOT EXISTS`, so re-running the script is safe.

## Repo Structure
```
sql_eda_project/
├── analysis.sql        # full annotated SQL script (cleaning -> EDA -> insights -> trends)
├── northwind.db         # SQLite database
├── run_queries.py       # runs every query in analysis.sql and prints results
└── README.md
```

## How to Run
```bash
# Option 1: any SQLite client
sqlite3 northwind.db
.read analysis.sql

# Option 2: Python
python3 run_queries.py
```

## Section 1 — Data Cleaning / Quality Checks
| Check | Result |
|---|---|
| Orphaned orders (no matching customer) | 0 |
| Orphaned order line items (no matching product) | 0 |
| Invalid quantity/price/discount values | 0 |
| Orders never shipped | **21** |
| Orders shipped before they were placed | 0 |
| Duplicate company names (case-insensitive) | **1 pair** — two distinct customers both named "IT" (`Val2`, `VALON`) |

The duplicate-name check is a good example of why data cleaning needs to look past primary
keys — these are two legitimately different customer records that would confuse any
name-based lookup or manual reporting.

## Section 2 — Exploratory Data Analysis
- **Total revenue:** $448.4M across 16,282 orders and 93 customers (SQLite-computed via
  `SUM(UnitPrice * Quantity * (1 - Discount))`)
- **Revenue by category:** Beverages leads at $92.2M, followed by Confections ($66.3M) and
  Meat/Poultry ($64.9M); Grains/Cereals is lowest at $28.6M
- **Average fulfillment time:** 7.84 days (range: 0-37 days)
- **Late shipments:** 3,755 orders (23.1%) shipped *after* the promised `RequiredDate` —
  a meaningful on-time-delivery problem worth flagging operationally

## Section 3 — Business Insights
- **Top product by revenue:** Côte de Blaye ($53.3M) — more than double the #2 product
  (Thüringer Rostbratwurst, $24.6M), making it a clear single-point-of-failure risk if that
  supplier has issues
- **Top customer:** B's Beverages ($6.15M lifetime revenue), ranked via `RANK() OVER (...)`
- **Employee performance:** revenue is fairly evenly spread across the 9 sales employees
  ($48.3M-$51.5M each) — no single rep is carrying the business, which is healthy, but also
  means there's no clear "top performer" playbook to replicate
- **Month-over-month revenue** swings noticeably (e.g. +72% in Aug 2012, -30% in Aug 2013) —
  computed with `LAG()` — worth pairing with a marketing/seasonality calendar to explain the swings
- **Discount usage is very low across the board** (0.01%-0.03% average discount rate per
  category) and clearly isn't a major revenue lever in this dataset — discounting isn't being
  used aggressively enough to draw conclusions about its effect on volume
- **8 customers** have gone 60+ days without ordering (average customer order gap is only
  ~27 days), flagging them as re-engagement targets — led by FISSA Fabrica Inter. Salchichas S.A.
  at 169 days
- **18 active products are at or below their reorder level**, including Gorgonzola Telino
  (0 units in stock, 70 on order) — a concrete restocking-priority list. (Query 3.7 has no
  `LIMIT`; `run_queries.py` prints only the first 15 rows of any result, so the true count is
  18, not 15 — worth remembering if a resume bullet or summary ever quotes the printed output
  instead of `COUNT(*)`.)

## Section 4 — Trends Over Time
- **Quarterly revenue is essentially flat, not growing:** a trailing 4-quarter rolling total
  (`SUM() OVER (... ROWS BETWEEN 3 PRECEDING AND CURRENT ROW)`) has stayed in a narrow
  $38M–$42M band from 2013 through 2023 — the month-to-month swings in Section 3 are noise
  around a plateau, not an actual growth or decline trend. (2023-Q4 is a partial quarter — the
  dataset ends mid-quarter — so its lower raw total isn't a real drop.)
- **Category mix has barely shifted in a decade:** Beverages' share of quarterly revenue has
  stayed in a tight 19.4%–22.1% band since 2012 (via `SUM() OVER (PARTITION BY quarter)`) — the
  category ranking in Section 2 isn't a snapshot, it's a decade-long structural pattern.
- **Côte de Blaye's dominance is structural, not worsening:** its share of *total company*
  revenue has held steady in the 10.5%–13.3% range every quarter since 2012 — the
  single-point-of-failure risk flagged in Section 3 isn't accelerating, but it also isn't
  resolving itself over time.

## Suggested Resume Bullets
- Performed SQL-only data cleaning and EDA on a 609K-row relational order database, identifying
  data-quality issues including duplicate customer records and 3,755 late shipments (23% of orders).
- Wrote CTE- and window-function-based queries (RANK, LAG, PARTITION BY, rolling window frames)
  to build customer/employee revenue leaderboards, quarterly trend analysis, and a rolling
  4-quarter revenue total across $448M in order revenue.
- Built a churn-risk and stockout-risk query set, surfacing 8 at-risk customer accounts and
  18 products below reorder threshold for operational follow-up.

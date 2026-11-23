# AP project: normalization (CP1)

App: **DolFin**, a financial statement and ratio analysis engine (Node, Express, Prisma, PostgreSQL).
Source of the data: `prisma/schema.prisma` (models `Stock`, `User` and `User_Stock`) and the Twelve Data `eod` and `statistics` responses used in `services/data_service.js`.
Nothing in the backend was changed to write this document. The tables below are the *proposed* final design that `dbms/03_schema.sql` (CP2) will create.

## 0. The data of the app

### 0.1 What the app stores today

| Model | Columns |
|---|---|
| `Stock` | id (PK), ticker (UNIQUE), name, price, last_price_date, market_cap, price_to_sales, year, quarter, gross_margin, operating_margin, return_on_assets, return_on_equity, revenue, ebitda, pat, total_cash, total_debt, debt_to_equity, current_ratio |
| `User` | id (PK), name, email (UNIQUE), password (a bcrypt hash, see `register.js`) |
| `User_Stock` | (userId, stockId) composite PK; userId → User(id), stockId → Stock(id), both ON DELETE CASCADE (read by `routes/dashboard_route.js`) |

### 0.2 Where the `Stock` values come from (unnormalized form)
One company comes back from the API as nested JSON (sample in `data_service.js`, Apple):

```
eod:        { symbol: AAPL, datetime: 2021-09-16, close: 148.79, ... }
statistics: { meta: { symbol: AAPL, name: "Apple Inc", ... },
              valuations_metrics: { market_capitalization, price_to_sales_ttm, ... },
              financials: { fiscal_year_ends: 2020-09-26, most_recent_quarter: 2021-06-26,
                            gross_margin, operating_margin, return_on_assets_ttm, return_on_equity_ttm,
                            income_statement: { revenue_ttm, ebitda, net_income_to_common_ttm, ... },
                            balance_sheet:    { total_cash_mrq, total_debt_mrq, total_debt_to_equity_mrq, current_ratio_mrq, ... } } }
```

Mapping to the `Stock` columns: `symbol` → ticker, `meta.name` → name, `close` → price, `datetime` → last_price_date, `market_capitalization` → market_cap, `price_to_sales_ttm` → price_to_sales, `fiscal_year_ends` → year, `most_recent_quarter` → quarter, and the margin, return, income statement and balance sheet fields keep their names.

## 1. First normal form (1NF)

1NF needs: atomic values, no repeating groups, and a primary key.

- The nested JSON is **not** 1NF (objects inside objects). Flattening it gives one row per company and fetch, which is what `Stock` is.
- After flattening, every column holds one atomic value and `Stock` has a primary key (`id`), so `Stock` and `User` are in 1NF. `User_Stock` has only its two key columns, both atomic, so it is in 1NF too.

Sample row of `Stock` (Apple, from the sample in the code; only some columns shown):

| id | ticker | name | price | last_price_date | market_cap | price_to_sales | year | quarter | gross_margin | revenue | total_debt |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | AAPL | Apple Inc | 148.79 | 2021-09-16 | 2546807865344 | 7.336227 | 2020-09-26 | 2021-06-26 | 46.57807 | 347155005440 | 135491002368 |

### Functional dependencies of `Stock`

The `year` and `quarter` columns exist because the app analyses a company **over reporting periods**, so the key that identifies a financial row is (ticker, year, quarter).

| # | Functional dependency | Meaning |
|---|---|---|
| F1 | ticker → name | one company name per ticker |
| F2 | ticker → price, last_price_date, market_cap, price_to_sales | the latest market snapshot of a company |
| F3 | (ticker, year, quarter) → gross_margin, operating_margin, return_on_assets, return_on_equity, revenue, ebitda, pat, total_cash, total_debt, debt_to_equity, current_ratio | the results of one reporting period |
| F4 | id → every column | surrogate key |
| F5 | ticker → id and id → ticker | `ticker` is UNIQUE, so it is an alternative key of the row |

Candidate key of the data as one wide table: **(ticker, year, quarter)**.

## 2. Second normal form (2NF)

2NF = 1NF + no non-key attribute depends on only a *part* of the candidate key.

`Stock` fails: `name`, `price`, `last_price_date`, `market_cap` and `price_to_sales` depend only on `ticker` (F1, F2), which is part of (ticker, year, quarter). Problems this causes when the same company has several quarters:

- **Update anomaly:** changing the price of AAPL means updating every quarter row of AAPL; missing one leaves two prices for one company.
- **Insert anomaly:** a company cannot be added (name, price) before it has a reported quarter.
- **Delete anomaly:** deleting the last quarter of a company also deletes its name and price.
- **Redundancy:** the name and market snapshot are repeated in every row.

Decomposition (remove the partial dependencies):

**company**(company_id PK, ticker UNIQUE, name, price, last_price_date, market_cap, price_to_sales)

**financial_report**(company_id FK → company, quarter_end, fiscal_year_end, gross_margin, operating_margin, return_on_assets, return_on_equity, revenue, ebitda, pat, total_cash, total_debt, debt_to_equity, current_ratio)  PK (company_id, quarter_end)

Column names against the backend: `year` → `fiscal_year_end` (API `fiscal_year_ends`), `quarter` → `quarter_end` (API `most_recent_quarter`), `ticker` in the report table is replaced by `company_id`, which is the same company (F5).

Check: in `financial_report` every non-key column depends on the whole key (a company's margins and revenue are for one particular quarter). `fiscal_year_end` depends on the whole key as well (a quarter belongs to one fiscal year of a company). So both tables are in 2NF.

## 3. Third normal form (3NF)

3NF = 2NF + no non-key attribute depends on another non-key attribute (no transitive dependency).

- **company:** the only determinants are `company_id` and `ticker`, and both are keys (F5). Nothing like price → market_cap is a real dependency, because market_cap also needs the number of shares, which the app does not store. 3NF holds.
- **financial_report:** the only determinant is the key (company_id, quarter_end). Some columns are ratios of other columns (for example debt_to_equity = total_debt / shareholders' equity), but the equity needed to compute them is not stored, and the app takes each value ready-made from the API, so no dependency between two non-key columns can be used to split the table. 3NF holds.

### The `User` table

| Functional dependency | |
|---|---|
| id → name, email, password | surrogate key |
| email → id, name, password | email is UNIQUE (login looks users up by email), so it is an alternative key |

`name` does not determine anything (two users can have the same name). The only determinants are keys, so `User` is in 3NF already. In the final schema it is called **app_user** (`user` is a reserved word in PostgreSQL) and the column `password` is named `password_hash`, because it holds the bcrypt hash.

**app_user**(user_id PK, name, email UNIQUE, password_hash)

### The `User_Stock` table

It has no non-key column: (userId, stockId) is the whole key, so there is nothing that can depend on part of the key or on another non-key column. It is in 2NF and 3NF already. In the final schema it is called **user_stock**, and `stockId` becomes `company_id` because `Stock` is split into company + financial_report and the stock a user saves is a company.

**user_stock**(user_id PK FK, company_id PK FK)

## 4. Boyce-Codd normal form (BCNF)

BCNF = for every functional dependency X → Y, X is a (super)key.

| Table | Determinants | All keys? |
|---|---|---|
| company | company_id, ticker | yes |
| financial_report | (company_id, quarter_end) | yes |
| app_user | user_id, email | yes |
| user_stock | (user_id, company_id) | yes |

All four tables are in **BCNF** (the optional level is reached without any further split).

## 5. Final tables

| Table | Primary key | Foreign keys | Other keys |
|---|---|---|---|
| company | company_id | none | UNIQUE (ticker) |
| financial_report | (company_id, quarter_end) | company_id → company(company_id) | none |
| user_stock | (user_id, company_id) | user_id → app_user(user_id) ON DELETE CASCADE, company_id → company(company_id) ON DELETE CASCADE | none |
| app_user | user_id | none | UNIQUE (email) |

Relationships: one company has many financial reports (1 : N); a user saves many companies and a company is saved by many users (M : N), resolved by `user_stock`.

## 6. Things found in the backend that the team should know about

These are observations only. Nothing was modified.

1. **`Stock.ticker` is UNIQUE together with `year` and `quarter` columns.** With that constraint a company can have only one row, so only one quarter of data can be saved per company, which cannot hold a history of periods. The split above (company + financial_report) removes the limit; in the current Prisma model it would need a change that was not made.
2. `Stock.year` and `Stock.quarter` are `DateTime`, so they hold dates, not a year number or a quarter number 1 to 4. The design keeps them as dates (`fiscal_year_end`, `quarter_end`) to match the API fields.
3. All numeric columns are `Decimal(65,30)` in the generated migration. The final schema can use a smaller `NUMERIC` precision.
4. `routes/data_route.js` and `services/data_service.js` are not wired into `server.js` yet and `data_service.js` has the typo `modules.export`, so the data fetch path has no queries to list yet. This matters for `dbms/04_queries.sql` (CP3): at the moment only login (`SELECT` by email) and register (`SELECT` by email, `INSERT`) really run.

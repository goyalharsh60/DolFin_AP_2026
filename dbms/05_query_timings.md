# AP project (DolFin): query timings (CP4)

> **These timings were measured on a synthetic database made for this exercise, not on real market data:** 100,000 users, 5,000 companies, 100,000 financial reports (20 quarters per company) and about 300,000 saved stocks (user_stock), random values. The app itself has no data of this size yet. Machine: a cloud container (2 vCPU / 8 GB), PostgreSQL 16, not a team laptop. **TEAM TO CHECK:** re-run on your own laptop if the course needs your machine and put its specs here.
> Method: every query was run 3 times with `EXPLAIN (ANALYZE, BUFFERS)` and the `Execution Time` line was read; the average of the 3 is in the table. WRITE queries ran inside `BEGIN; ... ROLLBACK;` so the data did not change. The full plans of all 3 runs of each query are in `dbms/plans/<id>.txt`. The queries are in `dbms/04_queries.sql`, the schema in `dbms/03_schema.sql`.

| Query | Type | What it does | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) | Scan type |
|-------|------|--------------|-----------:|-----------:|-----------:|-------------:|-----------|
| R1 | READ | login, find the user by email (then bcrypt compares the hash in the app) | 0.068 | 0.077 | 0.082 | 0.076 | Index Scan on app_user |
| R2 | READ | register, check whether the email already exists | 0.065 | 0.087 | 0.070 | 0.074 | Index Scan on app_user |
| R3 | READ | company page, latest market snapshot by ticker | 0.055 | 0.050 | 0.051 | 0.052 | Index Scan on company |
| R4 | READ | ratio history of one company, newest quarter first (JOIN company + financial_report) | 0.264 | 0.217 | 0.224 | 0.235 | Index Scan on company + Bitmap Heap Scan on financial_report |
| R5 | READ | latest quarter of every company with its snapshot (overview table) | 164.126 | 221.209 | 140.850 | 175.395 | Index Scan on company + Index Scan on financial_report |
| R6 | READ | screener, companies whose LATEST quarter has ROE above 15 and debt to equity below 100 | 44.414 | 63.555 | 46.285 | 51.418 | Seq Scan on company + Seq Scan on financial_report + Index Only Scan on financial_report |
| W1 | WRITE | register a user | 0.835 | 0.268 | 0.292 | 0.465 | — |
| W2 | WRITE | store the company snapshot fetched from the API (insert, or update when the ticker exists) | 0.313 | 0.302 | 0.307 | 0.307 | — |
| W3 | WRITE | store the latest quarter fetched from the API (insert, or update when already stored) | 0.441 | 0.275 | 0.375 | 0.364 | Index Scan on company |
| R7 | READ | a user's saved stocks with the latest quarter of each (JOIN user_stock, company, financial_report) | 0.329 | 0.163 | 0.237 | 0.243 | Index Only Scan on user_stock + Index Scan on company + Index Scan on financial_report |
| W4 | WRITE | save a stock to the user's portfolio (does nothing if already saved) | 0.601 | 0.729 | 0.525 | 0.618 | Index Scan on company |
| W5 | WRITE | remove a stock from the user's portfolio | 0.183 | 0.143 | 0.217 | 0.181 | Index Scan on company + Index Scan on user_stock |

## Query analysis

- **R1, R2, R3 (login, register check, company page):** a single Index Scan on the UNIQUE index (`uq_app_user_email`, `uq_company_ticker`), under 0.1 ms. These run on every request and stay fast because email and ticker each have a unique index. Without it, R1 would scan all 100,000 users.
- **R4 (ratio history of one company), 0.235 ms:** index lookup of the company by ticker, then a Bitmap Heap Scan of that company's 20 reports through the primary key `(company_id, quarter_end)`. The primary key already has `company_id` first, so no extra index was needed for the join.
- **R5 (latest quarter of every company), about 175 ms:** the slowest query. It has to look at all 100,000 reports (Merge Join over both primary keys, then an Incremental Sort to take the newest quarter per company, about 100,000 buffer hits) and returns 5,000 rows, so it is an overview query that reads everything. It is acceptable for a page that is opened rarely, but it grows with the number of reports. A different rewrite or a stored "latest report" column was not tried here.
- **R6 (screener), about 51 ms:** a Seq Scan of `financial_report` filtered by ROE and debt to equity (20,832 of 100,000 rows pass) is hashed, then a SubPlan runs 6,087 Index Only Scans to find each company's latest quarter (the plan prints the loop count). Nothing indexes `return_on_equity` or `debt_to_equity`, and at this size the planner chooses the full scan. No index was added or measured for it.
- **R7 (a user's saved stocks with the latest quarter of each), 0.243 ms:** Index Only Scan on the primary key of `user_stock` (it starts with `user_id`), then one lookup in `company` and one backward index scan of `financial_report` per saved stock. It reads only the few rows of one user, so the 300,000 rows of the table do not matter.
- **W1, W2, W3 (writes):** all below 0.5 ms. W2 and W3 are "insert or update" statements; they use the unique index on `ticker` and the primary key to detect the existing row.
- **W4, W5 (save and remove a stock from the portfolio):** W4 0.618 ms (the ticker lookup, then the insert with a conflict check on the primary key) and W5 0.181 ms (ticker lookup, then delete by primary key). Both are the cost of one row plus the primary-key index of `user_stock`.

## Limits of these numbers

- Only R1, R2, R7 and W1 are queries that the backend runs today (R7 is the `/dashboard` route, which reads only the stocks of a user; the plan here also adds the latest quarter). R3 to R6 and W2 to W5 are the queries the planned fetch, analysis and portfolio features need (see the header of `04_queries.sql`).
- The data is random, so for example the 20,832 rows that pass the R6 filter and the 5,000 rows of R5 would differ on real data.
- Run-to-run variation on the container is visible (the same query measured on another pass of the script can differ by tens of percent, most for R5 and R6); the averages above are from one pass of the script.

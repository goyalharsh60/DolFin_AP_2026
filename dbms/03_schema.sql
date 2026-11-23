-- =====================================================================
-- AP project (DolFin): final schema, PostgreSQL 15+
-- Tables come from dbms/01_normalization.md (all in BCNF).
-- Run:  psql -d <db> -f dbms/03_schema.sql
-- This is the normalized design of dbms/01_normalization.md. The Prisma model in the backend
-- (Stock / User / User_Stock) is the denormalized version of the same data.
-- =====================================================================
DROP TABLE IF EXISTS user_stock       CASCADE;
DROP TABLE IF EXISTS financial_report CASCADE;
DROP TABLE IF EXISTS company          CASCADE;
DROP TABLE IF EXISTS app_user         CASCADE;

-- Registered users of the app (backend: model User; register.js / auth_route.js)
CREATE TABLE app_user (
    user_id        INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name           TEXT NOT NULL CHECK (btrim(name) <> ''),
    email          TEXT NOT NULL,
    password_hash  TEXT NOT NULL,                 -- bcrypt hash, never the password itself
    CONSTRAINT uq_app_user_email UNIQUE (email),
    CONSTRAINT ck_app_user_email CHECK (position('@' IN email) > 1)
);

-- One row per listed company, with its latest market snapshot (Twelve Data: eod + statistics)
CREATE TABLE company (
    company_id       INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ticker           VARCHAR(20)   NOT NULL,
    name             TEXT          NOT NULL,
    price            NUMERIC(18,4) NOT NULL CHECK (price >= 0),
    last_price_date  DATE          NOT NULL,
    market_cap       NUMERIC(24,2) NOT NULL CHECK (market_cap >= 0),
    price_to_sales   NUMERIC(14,6) NOT NULL,
    CONSTRAINT uq_company_ticker UNIQUE (ticker)
);

-- Results of one reporting quarter of a company
CREATE TABLE financial_report (
    company_id        INTEGER       NOT NULL,
    quarter_end       DATE          NOT NULL,      -- API: most_recent_quarter
    fiscal_year_end   DATE          NOT NULL,      -- API: fiscal_year_ends
    gross_margin      NUMERIC(14,6) NOT NULL,
    operating_margin  NUMERIC(14,6) NOT NULL,
    return_on_assets  NUMERIC(14,6) NOT NULL,
    return_on_equity  NUMERIC(14,6) NOT NULL,
    revenue           NUMERIC(24,2) NOT NULL,
    ebitda            NUMERIC(24,2) NOT NULL,
    pat               NUMERIC(24,2) NOT NULL,      -- profit after tax (net income)
    total_cash        NUMERIC(24,2) NOT NULL CHECK (total_cash >= 0),
    total_debt        NUMERIC(24,2) NOT NULL CHECK (total_debt >= 0),
    debt_to_equity    NUMERIC(14,6) NOT NULL,
    current_ratio     NUMERIC(14,6) NOT NULL CHECK (current_ratio >= 0),
    CONSTRAINT pk_financial_report PRIMARY KEY (company_id, quarter_end),
    CONSTRAINT fk_report_company FOREIGN KEY (company_id)
        REFERENCES company (company_id) ON DELETE CASCADE,
    CONSTRAINT ck_report_year_after_quarter CHECK (fiscal_year_end <= quarter_end + 366)
);
-- The primary key (company_id, quarter_end) already serves "all reports of a company, newest first".

-- A user's saved stocks (portfolio): many users follow many companies (Prisma model User_Stock)
CREATE TABLE user_stock (
    user_id     INTEGER NOT NULL,
    company_id  INTEGER NOT NULL,
    CONSTRAINT pk_user_stock PRIMARY KEY (user_id, company_id),
    CONSTRAINT fk_user_stock_user    FOREIGN KEY (user_id)    REFERENCES app_user (user_id) ON DELETE CASCADE,
    CONSTRAINT fk_user_stock_company FOREIGN KEY (company_id) REFERENCES company (company_id) ON DELETE CASCADE
);
-- The primary key serves "all stocks of a user". "Which users follow a company" would need an index on
-- (company_id, user_id); no query of the app does that, so it is not created.

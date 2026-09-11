# sql-server-recipes

A practical SQL Server reference. Every script in this repository runs against a seeded sample database, and every
performance claim is backed by a measurement taken from it.

![SQL Server](https://img.shields.io/badge/SQL%20Server-2022-CC2927)
![T-SQL](https://img.shields.io/badge/T--SQL-Reference-blue)
![Docker](https://img.shields.io/badge/Docker-Enabled-2496ED)
![License](https://img.shields.io/badge/license-MIT-green)

## Description

Most SQL references either stop at syntax or jump straight to advanced topics without showing the cost of getting it
wrong. This one sits in between: each folder explains a technique, shows it working on realistic data volumes, and says
when **not** to use it.

The sample database holds 200 products, 2,000 customers, 20,000 orders and roughly 30,000 order items, which is enough
for index and plan differences to actually show up in the numbers.

## Objective

Be the reference worth keeping open in a second tab. No frontend, no application, just SQL that runs.

## Technologies

- SQL Server 2022
- T-SQL
- Docker, for a disposable instance to run everything against

## Contents

| Folder | Topics |
| --- | --- |
| [setup/](setup/) | Schema and seed data, run these first |
| [01-basics/](01-basics/) | `SELECT`, `WHERE`, `INSERT`, `UPDATE`, `DELETE`, `GROUP BY`, `GROUPING SETS` |
| [02-joins/](02-joins/) | `INNER`, `LEFT`, `RIGHT`, `FULL`, `CROSS`, self joins, anti joins, `APPLY` |
| [03-cte/](03-cte/) | Common table expressions, recursive hierarchies, date series |
| [04-window-functions/](04-window-functions/) | `ROW_NUMBER`, `RANK`, running totals, `LAG`, `LEAD`, gaps and islands |
| [05-pagination/](05-pagination/) | `OFFSET`/`FETCH` and keyset pagination, with the cost difference |
| [06-views/](06-views/) | Views, `SCHEMABINDING`, indexed views, `WITH CHECK OPTION` |
| [07-stored-procedures/](07-stored-procedures/) | Output parameters, table valued parameters, error handling, upserts |
| [08-triggers/](08-triggers/) | `AFTER` and `INSTEAD OF`, set based auditing, when not to use them |
| [09-indexes/](09-indexes/) | Clustered, covering, composite, filtered, plus usage diagnostics |
| [10-transactions/](10-transactions/) | Isolation levels, savepoints, `XACT_STATE`, deadlock handling |
| [11-json/](11-json/) | `FOR JSON`, `OPENJSON`, `JSON_VALUE`, indexing JSON properties |
| [12-performance/](12-performance/) | Diagnostics, and five measured bad vs good query comparisons |
| [examples/](examples/) | Complete reports: cohort retention, RFM segmentation, inventory alerts |

## Highlights

The [bad query vs good query](12-performance/bad-query-vs-good-query/) folder is the fastest way into the material.
Five pairs of queries returning identical results at very different cost, all measured on the seeded database:

| Case | Bad | Good | Difference |
| --- | --- | --- | --- |
| Sargability | 101 reads | 4 reads | 25x fewer reads |
| `SELECT *` | 159 reads | 25 reads | 6x fewer reads |
| Cursor vs set based | 76,408 ms | 47 ms | 1,600x faster |
| Implicit conversion | Index scan | Index seek | Plan shape changes |
| Correlated subquery | 477 reads, 3 passes | 159 reads, 1 pass | 3x fewer reads |

## How to run

### Start SQL Server with Docker

```bash
git clone https://github.com/lucas-goncalves-cav/sql-server-recipes.git
cd sql-server-recipes
cp .env.example .env
docker compose up -d
```

### Create the sample database

```bash
docker exec -i sql-recipes /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -C -i /scripts/setup/01-schema.sql

docker exec -i sql-recipes /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -C -i /scripts/setup/02-seed.sql
```

Or connect with SSMS or Azure Data Studio to `localhost,1433` and run the two files from `setup/`.

### Verify everything runs

```bash
./validate.sh
```

This spins up a disposable container, applies the schema and seed, executes every script in the repository, and reports
any that fail. It is how the scripts here are kept honest.

## Configuration

Copy `.env.example` to `.env` and set a password.

| Variable | Description | Default |
| --- | --- | --- |
| `MSSQL_SA_PASSWORD` | sa password for the container | `your_password_here` |
| `SQLSERVER_PORT` | Host port mapped to SQL Server | `1433` |

SQL Server rejects weak passwords. It must be at least 8 characters with three of: uppercase, lowercase, digits,
symbols. No real credentials are stored in this repository.

## Sample schema

```
Categories ──< Products ──< OrderItems >── Orders >── Customers

Employees ──< Employees        (self referencing, for recursive CTE examples)
```

| Table | Rows | Purpose |
| --- | --- | --- |
| `Categories` | 5 | Product grouping |
| `Products` | 200 | Catalog with price and stock |
| `Customers` | 2,000 | Spread across six states |
| `Orders` | 20,000 | Two years of history across five statuses |
| `OrderItems` | ~30,000 | One to three lines per order |
| `Employees` | 12 | Four level hierarchy |

## How to read a recipe

Each folder has a `README.md` explaining the technique, the trade offs and the common mistakes, plus `.sql` files with
runnable examples. The SQL files carry the detail in comments, so they stand on their own if you skip the README.

For anything performance related, turn on statistics before running:

```sql
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
```

And enable the actual execution plan, `Ctrl+M` in SSMS. Logical reads are the number to compare between two versions of
a query. Elapsed time depends on cache state and server load, logical reads do not.

## Roadmap

- [ ] Temporal tables and change tracking
- [ ] Partitioning large tables
- [ ] Full text search
- [ ] Columnstore indexes for analytical workloads
- [ ] Security: row level security, dynamic data masking, Always Encrypted

## License

Distributed under the MIT License. See [LICENSE](LICENSE) for details.

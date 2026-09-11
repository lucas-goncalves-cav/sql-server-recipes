# Window Functions

A window function computes a value over a set of rows related to the current row, without collapsing the result the way
`GROUP BY` does. Every detail row survives and gains the aggregate next to it.

## Files

| File | Content |
| --- | --- |
| `ranking.sql` | `ROW_NUMBER`, `RANK`, `DENSE_RANK`, `NTILE`, top N per group, deduplication |
| `aggregates.sql` | `SUM`/`AVG`/`COUNT` with `OVER`, running totals, moving averages, `ROWS` vs `RANGE` |
| `offset-functions.sql` | `LAG`, `LEAD`, `FIRST_VALUE`, `LAST_VALUE`, gaps and islands |

## Anatomy

```sql
FUNCTION() OVER (
    PARTITION BY <restart the window for each group>
    ORDER BY     <order inside the window>
    ROWS BETWEEN <frame start> AND <frame end>
)
```

## Ranking functions and ties

| Values | `ROW_NUMBER` | `RANK` | `DENSE_RANK` |
| --- | --- | --- | --- |
| 100 | 1 | 1 | 1 |
| 100 | 2 | 1 | 1 |
| 90 | 3 | 3 | 2 |
| 80 | 4 | 4 | 3 |

`ROW_NUMBER` is always unique, `RANK` skips after a tie, `DENSE_RANK` does not.

## Two things that surprise people

**A window function cannot go in `WHERE`.** `WHERE` is evaluated before `SELECT`, so the ranking does not exist yet.
Wrap the query in a CTE or derived table and filter outside.

**`LAST_VALUE` needs an explicit frame.** With `ORDER BY` present, the default frame is
`RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`, which ends at the current row, so `LAST_VALUE` returns the current
row. Use `ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING`.

## ROWS vs RANGE

`ROWS` counts physical rows. `RANGE` works on values, so rows sharing the `ORDER BY` value fall in the same frame.

When the ordering column has duplicates, the two produce different results. `RANGE` is also generally slower because it
may need a spool. When a running total is wanted, `ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW` is both explicit
and faster than relying on the default.

## Performance

A window function needs its input sorted by `PARTITION BY` then `ORDER BY`. An index matching that order removes the
sort operator from the plan:

```sql
CREATE NONCLUSTERED INDEX IX_Orders_Customer_Date
    ON dbo.Orders (CustomerId, OrderDate)
    INCLUDE (TotalAmount);
```

# Correlated Subquery vs Pre Aggregated Join

## Measured

Building a customer report with order count, revenue and last order date for all 2,000 customers:

| Version | `Orders` reads | `Orders` scan count |
| --- | --- | --- |
| `bad.sql` | 477 | 3 |
| `good.sql` | 159 | 1 |

Scan count tells the story: three separate passes over `Orders`, one per scalar subquery, versus one.

## Why

Each correlated scalar subquery is evaluated in the context of the outer row. Three subqueries means the optimizer
plans three separate accesses to `Orders`. Adding a fourth aggregate column would add a fourth pass.

Aggregating once and joining the result reads the table a single time no matter how many aggregate columns the report
needs. The cost stops growing with the width of the report.

## The gap widens with columns

| Aggregate columns | Correlated subqueries | Pre aggregated join |
| --- | --- | --- |
| 1 | 1 pass | 1 pass |
| 3 | 3 passes | 1 pass |
| 6 | 6 passes | 1 pass |

## When a correlated subquery is still right

`EXISTS` is correlated and is usually the best choice. It short circuits on the first matching row instead of computing
an aggregate:

```sql
-- Good: stops at the first match
WHERE EXISTS (SELECT 1 FROM dbo.Orders AS o WHERE o.CustomerId = c.CustomerId)

-- Wasteful: counts every row just to compare against zero
WHERE (SELECT COUNT(*) FROM dbo.Orders AS o WHERE o.CustomerId = c.CustomerId) > 0
```

## OUTER APPLY sits in between

`OUTER APPLY` is also evaluated per outer row, but it returns several columns from one execution, so it does not
multiply passes the way separate scalar subqueries do:

```sql
SELECT c.FullName, stats.OrderCount, stats.Revenue
FROM dbo.Customers AS c
OUTER APPLY (
    SELECT COUNT(*) AS OrderCount, SUM(TotalAmount) AS Revenue
    FROM dbo.Orders AS o
    WHERE o.CustomerId = c.CustomerId
) AS stats;
```

| Shape | Best for |
| --- | --- |
| Pre aggregated join | Reports covering most or all of the outer table |
| `OUTER APPLY` | Top N per group, or when the outer set is already filtered small |
| `EXISTS` | Existence checks, never `COUNT(*) > 0` |

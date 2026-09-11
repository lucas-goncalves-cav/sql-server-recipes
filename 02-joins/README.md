# Joins

## Files

| File | Content |
| --- | --- |
| `joins.sql` | `INNER`, `LEFT`, `RIGHT`, `FULL`, `CROSS`, self join, anti join |
| `apply.sql` | `CROSS APPLY` and `OUTER APPLY` |

## Which join keeps what

| Join | Rows kept |
| --- | --- |
| `INNER JOIN` | Only rows matching on both sides |
| `LEFT JOIN` | All left rows, `NULL` on the right when unmatched |
| `RIGHT JOIN` | All right rows, `NULL` on the left when unmatched |
| `FULL JOIN` | All rows from both sides |
| `CROSS JOIN` | Every combination, the Cartesian product |

## The mistake that turns a LEFT JOIN into an INNER JOIN

A filter on the right table belongs in the `ON` clause, not in `WHERE`. In `WHERE`, the `NULL` rows produced by the
outer join are filtered out and the join silently becomes an inner join:

```sql
-- Behaves like an INNER JOIN: rows with no order have Status = NULL and are discarded
SELECT c.FullName, o.OrderNumber
FROM dbo.Customers AS c
LEFT JOIN dbo.Orders AS o ON o.CustomerId = c.CustomerId
WHERE o.Status = 'Delivered';

-- Actually a LEFT JOIN: the condition restricts which orders match
SELECT c.FullName, o.OrderNumber
FROM dbo.Customers AS c
LEFT JOIN dbo.Orders AS o
    ON o.CustomerId = c.CustomerId
   AND o.Status = 'Delivered';
```

## Anti join

To find rows on the left with no counterpart on the right, both forms below work and produce the same plan in most
cases. `NOT EXISTS` reads better and is immune to the `NULL` trap that breaks `NOT IN`:

```sql
SELECT c.CustomerId
FROM dbo.Customers AS c
LEFT JOIN dbo.Orders AS o ON o.CustomerId = c.CustomerId
WHERE o.OrderId IS NULL;

SELECT c.CustomerId
FROM dbo.Customers AS c
WHERE NOT EXISTS (SELECT 1 FROM dbo.Orders AS o WHERE o.CustomerId = c.CustomerId);
```

## When to use APPLY instead of JOIN

`APPLY` evaluates the right side once per left row, so the right side can reference the left. Reach for it when:

- You need the top N rows per group and a window function would be heavier
- The right side is a table valued function
- You want to name a computed expression once and reuse it in the same `SELECT`

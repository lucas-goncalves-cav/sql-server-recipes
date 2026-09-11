# Basics

The four statements every query is built from, plus the filtering and aggregation clauses that surround them.

## Files

| File | Content |
| --- | --- |
| `select.sql` | Projection, aliases, `DISTINCT`, `TOP`, computed columns |
| `where.sql` | Comparison, `BETWEEN`, `IN`, `LIKE`, `NULL` handling |
| `insert.sql` | Single row, multi row, `INSERT ... SELECT`, `OUTPUT` |
| `update.sql` | Simple update, update with join, `OUTPUT` |
| `delete.sql` | Delete with filter, delete with join, `TRUNCATE` comparison |
| `group-by.sql` | Aggregations, `HAVING`, `GROUPING SETS`, `ROLLUP` |

## Things worth remembering

**`NULL` is not a value, it is the absence of one.** `WHERE ShippedDate = NULL` never matches a row. Use `IS NULL`.

**`WHERE` filters rows, `HAVING` filters groups.** `WHERE` runs before aggregation, `HAVING` runs after. Filtering in
`WHERE` whenever possible means fewer rows reach the aggregation step.

**`TOP` without `ORDER BY` is non deterministic.** SQL Server is free to return any rows. If order matters, say so.

**`TRUNCATE TABLE` is not a faster `DELETE`.** It deallocates pages instead of logging row deletions, cannot be filtered,
resets `IDENTITY`, and fails when the table is referenced by a foreign key.

## Logical processing order

SQL is written in one order and evaluated in another. This explains why a column alias defined in `SELECT` cannot be
used in `WHERE`, but can be used in `ORDER BY`:

```
FROM  ->  WHERE  ->  GROUP BY  ->  HAVING  ->  SELECT  ->  DISTINCT  ->  ORDER BY  ->  TOP / OFFSET
```

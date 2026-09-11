# Common Table Expressions

## Files

| File | Content |
| --- | --- |
| `cte-basics.sql` | Single and chained CTEs, CTEs as the source of a DML statement |
| `recursive-cte.sql` | Org chart traversal, subtree queries, date series generation |

## What a CTE is and is not

A CTE names a query expression so the statement that follows can reference it. It exists only for that one statement.

It is **not** a temporary table. SQL Server expands the CTE definition into the execution plan, so referencing the same
CTE twice evaluates the underlying query twice. When the result is expensive and reused, write it to a `#temp` table.

## Recursive CTE anatomy

```sql
WITH Name AS
(
    SELECT ...            -- anchor member: where recursion starts
    UNION ALL
    SELECT ...            -- recursive member: references Name
    FROM Source
    INNER JOIN Name ON ...
)
SELECT * FROM Name
OPTION (MAXRECURSION 1000);
```

The recursive member must eventually stop returning rows. `MAXRECURSION` defaults to 100, accepts up to 32767, and
`0` removes the limit. Hitting the limit raises an error and aborts the statement, which is a useful guard against a
cycle in the data.

## When to use each

| Need | Use |
| --- | --- |
| Break a long query into readable steps | CTE |
| Reference the result twice in one statement, cheaply | `#temp` table |
| Walk a parent/child hierarchy | Recursive CTE |
| Generate a range of dates or numbers | Recursive CTE or a numbers table |
| Reuse the definition across many queries | View or inline table valued function |

# Sargability

**S**earch **ARG**ument **able**: a predicate the engine can use to seek an index.

The rule is simple: **leave the column bare on the left side of the comparison.** The moment a column is wrapped in a
function, cast, or arithmetic, the index on it becomes unusable for seeking.

## The comparison

```sql
-- Bad: index on OrderDate cannot be used
WHERE YEAR(o.OrderDate) = 2026 AND MONTH(o.OrderDate) = 9

-- Good: seeks straight to the range
WHERE o.OrderDate >= @MonthStart AND o.OrderDate < @NextMonth
```

## Measured on the seeded 20,000 row table

Both run against the same covering index on `OrderDate`, filtering the current month:

| Version | Logical reads | Plan |
| --- | --- | --- |
| `bad.sql` | 101 | Index scan, every row evaluated |
| `good.sql` | 4 | Index seek, straight to the range |

Same index, same rows returned, 25 times the reads. The only difference is which side of the comparison the function
sits on.

## The same mistake in other clothes

```sql
WHERE UPPER(Name) = 'MOUSE'              -- bad, default collation is already case insensitive
WHERE Name = 'mouse'                     -- good

WHERE Price * 1.1 > 100                  -- bad
WHERE Price > 100 / 1.1                  -- good, arithmetic moved to the constant side

WHERE LEFT(Sku, 3) = 'SKU'               -- bad
WHERE Sku LIKE 'SKU%'                    -- good

WHERE DATEDIFF(DAY, OrderDate, GETDATE()) <= 30   -- bad
WHERE OrderDate >= DATEADD(DAY, -30, GETDATE())   -- good

WHERE ISNULL(ShippedDate, '9999-12-31') > @Date   -- bad
WHERE ShippedDate > @Date OR ShippedDate IS NULL  -- good
```

## Half open intervals

Prefer `>= start AND < end` over `BETWEEN` for anything with a time component:

```sql
-- Silently misses everything recorded after 00:00:00.000 on the 30th
WHERE OrderDate BETWEEN '2026-09-01' AND '2026-09-30'

-- Correct
WHERE OrderDate >= '2026-09-01' AND OrderDate < '2026-10-01'
```

## The escape hatch

When the expression genuinely cannot be rewritten, persist it as a computed column and index that:

```sql
ALTER TABLE dbo.Orders ADD OrderYearMonth AS (CONVERT(CHAR(7), OrderDate, 126)) PERSISTED;
CREATE NONCLUSTERED INDEX IX_Orders_YearMonth ON dbo.Orders (OrderYearMonth);
```

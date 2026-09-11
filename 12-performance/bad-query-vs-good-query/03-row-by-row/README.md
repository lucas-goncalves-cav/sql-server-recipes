# Row by Row vs Set Based

## Measured

Applying a 2 percent adjustment to `TotalAmount` on all 20,000 orders:

| Version | Elapsed | Ratio |
| --- | --- | --- |
| `bad.sql`, cursor | 76,408 ms | |
| `good.sql`, single `UPDATE` | 47 ms | 1,600x faster |

The cursor version takes over a minute. Be ready for that when running it.

## Why the gap is so large

The per row work is trivial in both cases. The difference is the fixed cost paid on every iteration:

- A separate `UPDATE` statement, each with its own plan lookup
- A lock acquired and released per row
- A separate log record per row
- A `FETCH NEXT` round trip per row

Twenty thousand times a small constant is a large number. The set based version pays that overhead once.

## The mental shift

SQL is declarative. Describe the result you want and let the optimizer decide how to produce it. A cursor takes that
decision away and hands the engine a fixed, serial plan it cannot improve.

Most cursors in production code are a loop that a `JOIN`, a window function, or a single `UPDATE ... FROM` could
replace:

```sql
-- A cursor updating each order from its items becomes:
UPDATE o
SET o.TotalAmount = t.Amount
FROM dbo.Orders AS o
INNER JOIN (
    SELECT OrderId, SUM(Quantity * UnitPrice * (1 - Discount)) AS Amount
    FROM dbo.OrderItems
    GROUP BY OrderId
) AS t ON t.OrderId = o.OrderId;
```

## When a loop is genuinely the right answer

- Calling a stored procedure that must run once per row, with side effects outside the database
- Administrative scripts iterating over databases, tables or indexes
- Deleting or updating millions of rows in bounded batches, to keep the log and lock footprint small

That last one is a loop over **batches**, not over rows:

```sql
WHILE 1 = 1
BEGIN
    DELETE TOP (5000) FROM dbo.Orders WHERE Status = 'Cancelled' AND OrderDate < @Cutoff;
    IF @@ROWCOUNT = 0 BREAK;
END;
```

## If a cursor is unavoidable

Declare it as narrowly as possible. The default cursor type is the most expensive one:

```sql
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT ...;
```

`LOCAL` limits scope, `FAST_FORWARD` makes it forward only and read only.

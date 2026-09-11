# Pagination

## Files

| File | Content |
| --- | --- |
| `offset-fetch.sql` | `OFFSET` / `FETCH`, tiebreakers, total row count |
| `keyset-pagination.sql` | Seek method, composite anchors, cost comparison |

## OFFSET / FETCH

```sql
SELECT ...
FROM dbo.Products
ORDER BY Name, ProductId
OFFSET (@Page - 1) * @PageSize ROWS
FETCH NEXT @PageSize ROWS ONLY;
```

`ORDER BY` is required. Add a unique tiebreaker to it, otherwise rows sharing the sort value can appear on two pages or
be skipped entirely.

## Why deep pages get slow

`OFFSET 100000` does not skip ahead. The server reads all 100,000 rows and throws them away. Cost grows linearly with
the page number, so the last page of a large table is the most expensive query in the application.

## Keyset pagination

Instead of counting rows to skip, remember where the last page ended and seek there:

```sql
SELECT TOP (@PageSize) ...
FROM dbo.Orders
WHERE OrderId > @LastOrderId
ORDER BY OrderId;
```

With an index on the ordering column this is an index seek at any depth, so page 1 and page 5,000 cost the same.

When ordering by a non unique column, compare the tuple:

```sql
WHERE (OrderDate > @LastDate)
   OR (OrderDate = @LastDate AND OrderId > @LastOrderId)
```

## Choosing between them

| | `OFFSET` / `FETCH` | Keyset |
| --- | --- | --- |
| Jump to page N | Yes | No |
| Cost at depth | Grows linearly | Constant |
| Stable under concurrent writes | No | Yes |
| Implementation effort | Trivial | Needs an anchor round trip |

Use `OFFSET` for admin tables where users page a few screens deep. Use keyset for infinite scroll, public APIs and any
dataset large enough that someone will reach page 500.

## Returning the total count

`COUNT(*) OVER ()` returns the total in the same pass, at the cost of repeating it on every row. A separate `COUNT(*)`
query is a second scan. For very large tables, consider not returning an exact total at all: most interfaces only need
to know whether a next page exists, which one extra row answers.

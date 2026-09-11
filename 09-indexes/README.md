# Indexes

## Files

| File | Content |
| --- | --- |
| `indexes.sql` | Clustered, nonclustered, covering, composite and filtered indexes, plus usage and fragmentation diagnostics |

## Measured effect

The same query, `SELECT OrderId, OrderNumber, TotalAmount FROM dbo.Orders WHERE CustomerId = 42`, against the seeded
20,000 row table. Logical reads reported by `SET STATISTICS IO ON`:

| Index | Logical reads | Plan |
| --- | --- | --- |
| None | 159 | Clustered index scan |
| `(CustomerId)` | 22 | Index seek plus key lookup |
| `(CustomerId) INCLUDE (OrderNumber, TotalAmount)` | 2 | Index seek, covering |

The lookup is what costs the difference between 22 and 2: the index found the rows but not the columns, so the engine
went back to the table once per row.

## Clustered index

The clustered index is the table. Its leaf level holds the rows themselves, in key order. One per table.

A good clustering key is:

- **Narrow**, because every nonclustered index stores a copy of it
- **Unique**, or SQL Server adds a 4 byte uniquifier
- **Static**, because changing it physically moves the row
- **Ever increasing**, to append at the end instead of splitting pages in the middle

An `IDENTITY` column meets all four. A random `GUID` as the clustering key meets none of them.

## Nonclustered index

A separate structure holding the key columns plus a pointer back to the row. When a query needs a column that is not in
the index, the engine performs a **key lookup** per row. A few lookups are cheap. Thousands are not, and the optimizer
will abandon the index and scan instead.

## Covering index

`INCLUDE` stores extra columns at the leaf level only:

```sql
CREATE NONCLUSTERED INDEX IX_Orders_CustomerId
    ON dbo.Orders (CustomerId)
    INCLUDE (OrderNumber, TotalAmount, OrderDate);
```

Included columns cannot be seeked or sorted on, but they eliminate the lookup and do not count toward the 900 byte key
size limit.

## Composite index column order

An index on `(A, B)` can seek on `A` and on `A + B`. It cannot seek on `B` alone.

The rule: **equality columns first, the range column last.**

```sql
-- Seeks: equality on Status narrows first, then the range on OrderDate
WHERE Status = 'Delivered' AND OrderDate >= @From

-- Index on (OrderDate, Status) would seek the range then filter, reading far more
```

## Filtered index

When queries always target a small slice, index only that slice:

```sql
CREATE NONCLUSTERED INDEX IX_Orders_PendingOnly
    ON dbo.Orders (OrderDate)
    WHERE Status = 'Pending';
```

Smaller, faster to maintain, and only usable when the query predicate matches the index predicate.

## What stops an index from being used

```sql
WHERE YEAR(OrderDate) = 2026              -- function on the column, not sargable
WHERE OrderDate >= '2026-01-01'           -- sargable
  AND OrderDate <  '2027-01-01'

WHERE Name LIKE '%mouse'                  -- leading wildcard, scan
WHERE Name LIKE 'mouse%'                  -- seek

WHERE CAST(CustomerId AS VARCHAR) = '42'  -- implicit conversion, scan
WHERE CustomerId = 42                     -- seek
```

An implicit conversion on the **column** side is the one that hurts. A conversion on the parameter side is fine.

## The cost side

Every index is maintained on every `INSERT`, `UPDATE` and `DELETE` touching its columns. Indexes are not free storage
for maybe useful lookups. Find the ones that only ever cost:

```sql
SELECT OBJECT_NAME(s.object_id), i.name, s.user_updates
FROM sys.dm_db_index_usage_stats AS s
INNER JOIN sys.indexes AS i ON i.object_id = s.object_id AND i.index_id = s.index_id
WHERE s.user_seeks = 0 AND s.user_scans = 0 AND s.user_lookups = 0
  AND i.type_desc = 'NONCLUSTERED';
```

These counters reset when the instance restarts, so read them after a representative period, not right after a reboot.

## Fragmentation

| Fragmentation | Action |
| --- | --- |
| Below 10 percent | Leave it alone |
| 10 to 30 percent | `ALTER INDEX ... REORGANIZE` |
| Above 30 percent | `ALTER INDEX ... REBUILD` |

Ignore fragmentation on indexes under roughly 1,000 pages. The maintenance costs more than the fragmentation.

## On missing index suggestions

`sys.dm_db_missing_index_details` and the green hint in a plan are starting points, not instructions. They ignore the
indexes you already have, never propose changing column order on an existing index, list included columns
alphabetically rather than usefully, and score each suggestion in isolation. Blindly creating all of them is how a
table ends up with fifteen overlapping indexes.

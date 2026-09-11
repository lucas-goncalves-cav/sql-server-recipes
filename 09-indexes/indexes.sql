/*
    Indexes: what each type does and how to tell whether one is being used.

    Run with the actual execution plan on (Ctrl+M in SSMS) to see seeks,
    scans, key lookups and missing index hints.
*/

USE SqlRecipes;
GO

SET STATISTICS IO ON;
GO

/* ------------------------------------------------------------------------- */
/* Clustered index                                                            */
/* ------------------------------------------------------------------------- */
/*
    The clustered index IS the table: the leaf level holds the actual rows,
    stored in key order. A table can have exactly one.

    A good clustering key is narrow, unique, static and ever increasing.
    Every nonclustered index carries a copy of it, so a wide clustering key
    inflates every other index on the table.
*/
SELECT
    i.name              AS IndexName,
    i.type_desc         AS IndexType,
    i.is_unique,
    STRING_AGG(c.name, ', ') WITHIN GROUP (ORDER BY ic.key_ordinal) AS KeyColumns
FROM sys.indexes AS i
INNER JOIN sys.index_columns AS ic
    ON ic.object_id = i.object_id AND ic.index_id = i.index_id
INNER JOIN sys.columns AS c
    ON c.object_id = ic.object_id AND c.column_id = ic.column_id
WHERE i.object_id = OBJECT_ID('dbo.Orders')
  AND ic.is_included_column = 0
GROUP BY i.name, i.type_desc, i.is_unique;
GO

/* ------------------------------------------------------------------------- */
/* Nonclustered index                                                         */
/* ------------------------------------------------------------------------- */
/* Without an index this filter forces a scan of the whole clustered index. */
PRINT '--- Before the index ---';
SELECT o.OrderId, o.OrderNumber, o.TotalAmount
FROM dbo.Orders AS o
WHERE o.CustomerId = 42;
GO

CREATE NONCLUSTERED INDEX IX_Orders_CustomerId
    ON dbo.Orders (CustomerId);
GO

/*
    Now the filter seeks, but TotalAmount and OrderNumber are not in the index.
    SQL Server has to go back to the clustered index once per matching row:
    a key lookup. Cheap for a handful of rows, expensive for thousands.
*/
PRINT '--- Seek plus key lookup ---';
SELECT o.OrderId, o.OrderNumber, o.TotalAmount
FROM dbo.Orders AS o
WHERE o.CustomerId = 42;
GO

/* ------------------------------------------------------------------------- */
/* Covering index                                                             */
/* ------------------------------------------------------------------------- */
/*
    INCLUDE stores extra columns at the leaf level only. They cannot be used
    for seeking or ordering, but they remove the key lookup, and they do not
    count against the 900 byte key size limit.
*/
DROP INDEX IF EXISTS IX_Orders_CustomerId ON dbo.Orders;
GO

CREATE NONCLUSTERED INDEX IX_Orders_CustomerId_Covering
    ON dbo.Orders (CustomerId)
    INCLUDE (OrderNumber, TotalAmount, OrderDate);
GO

PRINT '--- Covering index, no lookup ---';
SELECT o.OrderId, o.OrderNumber, o.TotalAmount
FROM dbo.Orders AS o
WHERE o.CustomerId = 42;
GO

/* ------------------------------------------------------------------------- */
/* Composite index and column order                                           */
/* ------------------------------------------------------------------------- */
/*
    Column order decides which queries can seek. An index on (A, B) can seek
    on A, and on A + B, but not on B alone. Put the equality columns first,
    the range column last.
*/
CREATE NONCLUSTERED INDEX IX_Orders_Status_OrderDate
    ON dbo.Orders (Status, OrderDate)
    INCLUDE (CustomerId, TotalAmount);
GO

PRINT '--- Seeks: equality on Status, range on OrderDate ---';
SELECT o.OrderId, o.CustomerId, o.TotalAmount
FROM dbo.Orders AS o
WHERE o.Status = 'Delivered'
  AND o.OrderDate >= DATEADD(DAY, -90, SYSUTCDATETIME());
GO

PRINT '--- Scans: the leading column is missing from the predicate ---';
SELECT o.OrderId, o.CustomerId
FROM dbo.Orders AS o
WHERE o.OrderDate >= DATEADD(DAY, -90, SYSUTCDATETIME());
GO

/* ------------------------------------------------------------------------- */
/* Filtered index                                                             */
/* ------------------------------------------------------------------------- */
/*
    When queries always target a small slice of the table, indexing only that
    slice keeps the index small and cheap to maintain.
*/
CREATE NONCLUSTERED INDEX IX_Orders_PendingOnly
    ON dbo.Orders (OrderDate)
    INCLUDE (CustomerId, TotalAmount)
    WHERE Status = 'Pending';
GO

PRINT '--- Filtered index: predicate must match the index definition ---';
SELECT o.OrderId, o.CustomerId, o.TotalAmount
FROM dbo.Orders AS o
WHERE o.Status = 'Pending'
  AND o.OrderDate >= DATEADD(DAY, -30, SYSUTCDATETIME());
GO

/* ------------------------------------------------------------------------- */
/* Diagnostics                                                                */
/* ------------------------------------------------------------------------- */
SET STATISTICS IO OFF;
GO

/* Index usage: seeks and scans are value, updates are cost. */
SELECT
    OBJECT_NAME(s.object_id) AS TableName,
    i.name                   AS IndexName,
    s.user_seeks,
    s.user_scans,
    s.user_lookups,
    s.user_updates
FROM sys.dm_db_index_usage_stats AS s
INNER JOIN sys.indexes AS i
    ON i.object_id = s.object_id AND i.index_id = s.index_id
WHERE s.database_id = DB_ID()
  AND OBJECT_NAME(s.object_id) IN ('Orders', 'Products', 'Customers', 'OrderItems')
ORDER BY TableName, IndexName;
GO

/*
    Indexes that are only ever written to. High user_updates with zero reads
    means the index is pure overhead. Check over a representative window,
    since these counters reset when the instance restarts.
*/
SELECT
    OBJECT_NAME(s.object_id) AS TableName,
    i.name                   AS UnusedIndex,
    s.user_updates           AS WritesMaintained
FROM sys.dm_db_index_usage_stats AS s
INNER JOIN sys.indexes AS i
    ON i.object_id = s.object_id AND i.index_id = s.index_id
WHERE s.database_id = DB_ID()
  AND i.type_desc = 'NONCLUSTERED'
  AND s.user_seeks = 0
  AND s.user_scans = 0
  AND s.user_lookups = 0
ORDER BY s.user_updates DESC;
GO

/* Fragmentation. Reorganize above 10 percent, rebuild above 30. */
SELECT
    OBJECT_NAME(ps.object_id)        AS TableName,
    i.name                           AS IndexName,
    CAST(ps.avg_fragmentation_in_percent AS DECIMAL(5, 2)) AS FragmentationPercent,
    ps.page_count
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') AS ps
INNER JOIN sys.indexes AS i
    ON i.object_id = ps.object_id AND i.index_id = ps.index_id
WHERE ps.page_count > 100
ORDER BY ps.avg_fragmentation_in_percent DESC;
GO

/*
    Missing index suggestions from the optimizer. Treat them as hints, not
    orders: they ignore existing indexes, never suggest column order changes,
    and each suggestion is scored in isolation.
*/
SELECT TOP (10)
    ROUND(s.avg_total_user_cost * s.avg_user_impact * (s.user_seeks + s.user_scans), 0) AS EstimatedImpact,
    d.statement    AS TableName,
    d.equality_columns,
    d.inequality_columns,
    d.included_columns
FROM sys.dm_db_missing_index_groups AS g
INNER JOIN sys.dm_db_missing_index_group_stats AS s
    ON s.group_handle = g.index_group_handle
INNER JOIN sys.dm_db_missing_index_details AS d
    ON d.index_handle = g.index_handle
WHERE d.database_id = DB_ID()
ORDER BY EstimatedImpact DESC;
GO

/* ------------------------------------------------------------------------- */
/* Cleanup                                                                    */
/* ------------------------------------------------------------------------- */
DROP INDEX IF EXISTS IX_Orders_CustomerId_Covering ON dbo.Orders;
DROP INDEX IF EXISTS IX_Orders_Status_OrderDate    ON dbo.Orders;
DROP INDEX IF EXISTS IX_Orders_PendingOnly         ON dbo.Orders;
GO

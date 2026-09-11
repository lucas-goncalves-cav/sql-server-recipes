/*
    DELETE: filtered deletes, deletes driven by a join, and how TRUNCATE differs.
*/

USE SqlRecipes;
GO

/* Preview what a DELETE would remove before running it. */
SELECT COUNT(*) AS RowsThatWouldBeDeleted
FROM dbo.Orders AS o
WHERE o.Status = 'Cancelled'
  AND o.OrderDate < DATEADD(YEAR, -1, SYSUTCDATETIME());
GO

/* DELETE with a join: the DELETE targets the alias. */
CREATE TABLE #Removable (OrderId INT PRIMARY KEY);

INSERT INTO #Removable (OrderId)
SELECT TOP (5) o.OrderId
FROM dbo.Orders AS o
WHERE o.Status = 'Cancelled'
ORDER BY o.OrderId DESC;

DELETE o
OUTPUT deleted.OrderId, deleted.OrderNumber
FROM dbo.Orders AS o
INNER JOIN #Removable AS r
    ON r.OrderId = o.OrderId;

DROP TABLE #Removable;
GO

/*
    Deleting millions of rows in one statement holds locks and grows the log.
    Batching keeps each transaction small and lets other sessions through.
*/
SET NOCOUNT ON;

WHILE 1 = 1
BEGIN
    DELETE TOP (1000)
    FROM dbo.Orders
    WHERE Status = 'Cancelled'
      AND OrderDate < DATEADD(YEAR, -5, SYSUTCDATETIME());

    IF @@ROWCOUNT = 0
        BREAK;
END;

SET NOCOUNT OFF;
GO

/*
    DELETE vs TRUNCATE TABLE

    DELETE
        - Logs every row, can be filtered, fires triggers
        - Keeps the current IDENTITY value
        - Works when the table is referenced by a foreign key

    TRUNCATE TABLE
        - Deallocates pages, minimal logging, much faster
        - Cannot be filtered and does not fire DELETE triggers
        - Resets IDENTITY back to the seed
        - Fails if any foreign key references the table

    Both are transactional in SQL Server and can be rolled back.
*/

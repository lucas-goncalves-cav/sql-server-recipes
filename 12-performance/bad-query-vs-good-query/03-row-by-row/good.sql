/*
    GOOD: one set based statement.

    The optimizer sees the whole operation, builds a single plan, and the
    storage engine writes the changes in batches instead of one round trip
    per row.
*/

USE SqlRecipes;
GO

DECLARE @Start DATETIME2(3) = SYSUTCDATETIME();

UPDATE dbo.Orders
SET TotalAmount = TotalAmount * 1.02;

SELECT
    @@ROWCOUNT                                            AS RowsUpdated,
    DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME())       AS SetBasedElapsedMs;
GO

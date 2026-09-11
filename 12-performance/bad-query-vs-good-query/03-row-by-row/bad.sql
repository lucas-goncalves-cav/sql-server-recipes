/*
    BAD: a cursor updating one row at a time.

    Sometimes called RBAR, row by agonizing row. Each iteration is a separate
    statement with its own execution, its own locks and its own log records.
    The work per row is tiny, but it is paid 20,000 times.
*/

USE SqlRecipes;
GO

DECLARE @Start DATETIME2(3) = SYSUTCDATETIME();

DECLARE @OrderId INT;
DECLARE @Adjusted DECIMAL(18, 2);

DECLARE order_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT OrderId, TotalAmount * 1.02
    FROM dbo.Orders;

OPEN order_cursor;
FETCH NEXT FROM order_cursor INTO @OrderId, @Adjusted;

WHILE @@FETCH_STATUS = 0
BEGIN
    UPDATE dbo.Orders
    SET TotalAmount = @Adjusted
    WHERE OrderId = @OrderId;

    FETCH NEXT FROM order_cursor INTO @OrderId, @Adjusted;
END;

CLOSE order_cursor;
DEALLOCATE order_cursor;

SELECT DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME()) AS CursorElapsedMs;
GO

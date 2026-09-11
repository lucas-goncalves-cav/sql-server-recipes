/*
    GOOD: the column is left alone and the range is expressed on the boundaries.

    The predicate is now sargable, so the index on OrderDate can seek directly
    to the start of the range and stop at the end.

    Note the half open interval: >= start AND < next month. Using BETWEEN with
    the last day of the month would silently drop rows recorded during that day.
*/

USE SqlRecipes;
GO

DECLARE @MonthStart DATETIME2(3) = DATEFROMPARTS(YEAR(SYSUTCDATETIME()), MONTH(SYSUTCDATETIME()), 1);
DECLARE @NextMonth  DATETIME2(3) = DATEADD(MONTH, 1, @MonthStart);

SET STATISTICS IO ON;

SELECT o.OrderId, o.OrderNumber, o.TotalAmount
FROM dbo.Orders AS o
WHERE o.OrderDate >= @MonthStart
  AND o.OrderDate <  @NextMonth;

SET STATISTICS IO OFF;
GO

DROP INDEX IF EXISTS IX_Orders_OrderDate ON dbo.Orders;
GO

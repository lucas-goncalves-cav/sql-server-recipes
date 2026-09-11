/*
    BAD: a function wrapped around the indexed column.

    YEAR(OrderDate) must be evaluated for every row before it can be compared,
    so the index on OrderDate cannot be used to seek. The plan is a full scan
    regardless of how selective the filter is.
*/

USE SqlRecipes;
GO

CREATE NONCLUSTERED INDEX IX_Orders_OrderDate
    ON dbo.Orders (OrderDate)
    INCLUDE (OrderNumber, TotalAmount);
GO

SET STATISTICS IO ON;

SELECT o.OrderId, o.OrderNumber, o.TotalAmount
FROM dbo.Orders AS o
WHERE YEAR(o.OrderDate) = YEAR(SYSUTCDATETIME())
  AND MONTH(o.OrderDate) = MONTH(SYSUTCDATETIME());

SET STATISTICS IO OFF;
GO

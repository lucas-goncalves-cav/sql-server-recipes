/*
    GOOD: name the columns the caller actually consumes.

    The same index now covers the query end to end, so the clustered index is
    never touched.
*/

USE SqlRecipes;
GO

SET STATISTICS IO ON;

SELECT
    o.OrderNumber,
    o.Status,
    o.TotalAmount
FROM dbo.Orders AS o
WHERE o.Status = 'Delivered';

SET STATISTICS IO OFF;
GO

DROP INDEX IF EXISTS IX_Orders_Status_Covering ON dbo.Orders;
GO

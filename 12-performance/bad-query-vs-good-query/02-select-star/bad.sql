/*
    BAD: SELECT * when only three columns are needed.

    Every column is read and sent over the wire, so a covering index cannot
    cover the query and the engine must fall back to the clustered index.
*/

USE SqlRecipes;
GO

CREATE NONCLUSTERED INDEX IX_Orders_Status_Covering
    ON dbo.Orders (Status)
    INCLUDE (OrderNumber, TotalAmount);
GO

SET STATISTICS IO ON;

SELECT *
FROM dbo.Orders AS o
WHERE o.Status = 'Delivered';

SET STATISTICS IO OFF;
GO

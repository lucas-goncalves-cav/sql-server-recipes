/*
    BAD: a correlated scalar subquery per column, per row.

    Each subquery is evaluated once for every row of the outer query. Three
    aggregates means three passes over Orders for each customer.
*/

USE SqlRecipes;
GO

SET STATISTICS IO ON;

SELECT
    c.CustomerId,
    c.FullName,
    (SELECT COUNT(*)            FROM dbo.Orders AS o WHERE o.CustomerId = c.CustomerId) AS OrderCount,
    (SELECT SUM(o.TotalAmount)  FROM dbo.Orders AS o WHERE o.CustomerId = c.CustomerId) AS Revenue,
    (SELECT MAX(o.OrderDate)    FROM dbo.Orders AS o WHERE o.CustomerId = c.CustomerId) AS LastOrderDate
FROM dbo.Customers AS c;

SET STATISTICS IO OFF;
GO

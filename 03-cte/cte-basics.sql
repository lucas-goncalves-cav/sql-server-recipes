/*
    Common Table Expressions: naming a subquery to keep a query readable.
*/

USE SqlRecipes;
GO

/* A CTE is scoped to the single statement that follows it. */
WITH CustomerRevenue AS
(
    SELECT
        o.CustomerId,
        COUNT(*)           AS OrderCount,
        SUM(o.TotalAmount) AS Revenue
    FROM dbo.Orders AS o
    WHERE o.Status <> 'Cancelled'
    GROUP BY o.CustomerId
)
SELECT
    c.FullName,
    c.State,
    r.OrderCount,
    r.Revenue
FROM CustomerRevenue AS r
INNER JOIN dbo.Customers AS c
    ON c.CustomerId = r.CustomerId
WHERE r.Revenue > 15000.00
ORDER BY r.Revenue DESC;
GO

/* Several CTEs chain with commas and can reference the previous ones. */
WITH OrderTotals AS
(
    SELECT
        oi.OrderId,
        SUM(oi.Quantity * oi.UnitPrice * (1 - oi.Discount)) AS ComputedTotal
    FROM dbo.OrderItems AS oi
    GROUP BY oi.OrderId
),
Mismatched AS
(
    SELECT
        o.OrderId,
        o.OrderNumber,
        o.TotalAmount,
        t.ComputedTotal,
        ABS(o.TotalAmount - t.ComputedTotal) AS Difference
    FROM dbo.Orders AS o
    INNER JOIN OrderTotals AS t
        ON t.OrderId = o.OrderId
)
SELECT TOP (20) *
FROM Mismatched
WHERE Difference > 0.01
ORDER BY Difference DESC;
GO

/* A CTE can also be the source of an UPDATE or DELETE. */
WITH Stale AS
(
    SELECT o.OrderId
    FROM dbo.Orders AS o
    WHERE o.Status = 'Pending'
      AND o.OrderDate < DATEADD(YEAR, -2, SYSUTCDATETIME())
)
SELECT COUNT(*) AS StalePendingOrders FROM Stale;
GO

/*
    A CTE is not a temporary table. SQL Server inlines it into the plan, so
    referencing the same CTE twice evaluates it twice. When the result is
    expensive and reused, materialize it in a #temp table instead.
*/

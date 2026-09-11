/*
    GROUP BY: aggregation, HAVING, GROUPING SETS, ROLLUP and CUBE.
*/

USE SqlRecipes;
GO

/* Every non aggregated column in SELECT must appear in GROUP BY. */
SELECT
    c.Name                AS Category,
    COUNT(*)              AS ProductCount,
    AVG(p.UnitPrice)      AS AveragePrice,
    MIN(p.UnitPrice)      AS CheapestPrice,
    MAX(p.UnitPrice)      AS MostExpensivePrice
FROM dbo.Products AS p
INNER JOIN dbo.Categories AS c
    ON c.CategoryId = p.CategoryId
GROUP BY c.Name
ORDER BY ProductCount DESC;
GO

/*
    COUNT(*) counts rows. COUNT(column) counts rows where the column is not NULL.
    The difference is how many orders have never shipped.
*/
SELECT
    COUNT(*)              AS TotalOrders,
    COUNT(o.ShippedDate)  AS ShippedOrders,
    COUNT(*) - COUNT(o.ShippedDate) AS NeverShipped
FROM dbo.Orders AS o;
GO

/* WHERE filters rows before grouping, HAVING filters groups after. */
SELECT
    o.CustomerId,
    COUNT(*)          AS OrderCount,
    SUM(o.TotalAmount) AS Revenue
FROM dbo.Orders AS o
WHERE o.Status <> 'Cancelled'          -- fewer rows reach the aggregation
GROUP BY o.CustomerId
HAVING SUM(o.TotalAmount) > 20000.00   -- evaluated against the aggregated value
ORDER BY Revenue DESC;
GO

/* Conditional aggregation avoids scanning the table once per status. */
SELECT
    c.State,
    COUNT(*)                                                   AS TotalOrders,
    SUM(CASE WHEN o.Status = 'Delivered' THEN 1 ELSE 0 END)    AS Delivered,
    SUM(CASE WHEN o.Status = 'Cancelled' THEN 1 ELSE 0 END)    AS Cancelled,
    SUM(CASE WHEN o.Status = 'Delivered' THEN o.TotalAmount END) AS DeliveredRevenue
FROM dbo.Orders AS o
INNER JOIN dbo.Customers AS c
    ON c.CustomerId = o.CustomerId
GROUP BY c.State
ORDER BY TotalOrders DESC;
GO

/* GROUPING SETS produces several groupings in a single pass over the data. */
SELECT
    c.State,
    o.Status,
    COUNT(*) AS OrderCount
FROM dbo.Orders AS o
INNER JOIN dbo.Customers AS c
    ON c.CustomerId = o.CustomerId
GROUP BY GROUPING SETS
(
    (c.State, o.Status),
    (c.State),
    ()
)
ORDER BY c.State, o.Status;
GO

/* ROLLUP adds subtotals following the column hierarchy, plus a grand total. */
SELECT
    COALESCE(c.State, 'ALL STATES') AS State,
    COALESCE(o.Status, 'ALL')       AS Status,
    SUM(o.TotalAmount)              AS Revenue,
    GROUPING(o.Status)              AS IsStatusSubtotal
FROM dbo.Orders AS o
INNER JOIN dbo.Customers AS c
    ON c.CustomerId = o.CustomerId
GROUP BY ROLLUP (c.State, o.Status)
ORDER BY c.State, o.Status;
GO

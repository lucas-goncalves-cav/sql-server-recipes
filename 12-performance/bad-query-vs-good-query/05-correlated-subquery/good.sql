/*
    GOOD: aggregate once, join once.

    Orders is read a single time. The aggregate is computed for every customer
    in one pass and joined back.

    OUTER APPLY would also work and keeps customers with no orders, at the cost
    of one execution per outer row. For a full table report, the pre aggregated
    join wins. For "top N per customer", APPLY wins.
*/

USE SqlRecipes;
GO

SET STATISTICS IO ON;

SELECT
    c.CustomerId,
    c.FullName,
    ISNULL(o.OrderCount, 0)   AS OrderCount,
    ISNULL(o.Revenue, 0)      AS Revenue,
    o.LastOrderDate
FROM dbo.Customers AS c
LEFT JOIN
(
    SELECT
        CustomerId,
        COUNT(*)           AS OrderCount,
        SUM(TotalAmount)   AS Revenue,
        MAX(OrderDate)     AS LastOrderDate
    FROM dbo.Orders
    GROUP BY CustomerId
) AS o
    ON o.CustomerId = c.CustomerId;

SET STATISTICS IO OFF;
GO

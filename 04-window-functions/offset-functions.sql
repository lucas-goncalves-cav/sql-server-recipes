/*
    Offset window functions: LAG, LEAD, FIRST_VALUE, LAST_VALUE.

    These read another row inside the same partition without a self join.
*/

USE SqlRecipes;
GO

/* LAG reads backwards, LEAD reads forwards. The third argument is the default. */
WITH MonthlyRevenue AS
(
    SELECT
        DATEFROMPARTS(YEAR(o.OrderDate), MONTH(o.OrderDate), 1) AS [Month],
        SUM(o.TotalAmount)                                      AS Revenue
    FROM dbo.Orders AS o
    WHERE o.Status <> 'Cancelled'
    GROUP BY DATEFROMPARTS(YEAR(o.OrderDate), MONTH(o.OrderDate), 1)
)
SELECT
    [Month],
    Revenue,
    LAG(Revenue, 1, 0)  OVER (ORDER BY [Month]) AS PreviousMonth,
    LEAD(Revenue, 1, 0) OVER (ORDER BY [Month]) AS NextMonth,
    Revenue - LAG(Revenue, 1, 0) OVER (ORDER BY [Month]) AS AbsoluteChange,
    CASE
        WHEN LAG(Revenue) OVER (ORDER BY [Month]) IS NULL THEN NULL
        WHEN LAG(Revenue) OVER (ORDER BY [Month]) = 0 THEN NULL
        ELSE CAST(100.0 * (Revenue - LAG(Revenue) OVER (ORDER BY [Month]))
                  / LAG(Revenue) OVER (ORDER BY [Month]) AS DECIMAL(8, 2))
    END AS PercentChange
FROM MonthlyRevenue
ORDER BY [Month];
GO

/* Time between consecutive orders of the same customer. */
SELECT TOP (30)
    o.CustomerId,
    o.OrderNumber,
    o.OrderDate,
    LAG(o.OrderDate) OVER (PARTITION BY o.CustomerId ORDER BY o.OrderDate) AS PreviousOrderDate,
    DATEDIFF(DAY,
             LAG(o.OrderDate) OVER (PARTITION BY o.CustomerId ORDER BY o.OrderDate),
             o.OrderDate) AS DaysSincePreviousOrder
FROM dbo.Orders AS o
WHERE o.CustomerId <= 3
ORDER BY o.CustomerId, o.OrderDate;
GO

/*
    FIRST_VALUE works with the default frame. LAST_VALUE does not: the default
    frame ends at the current row, so it returns the current row itself.
    Widen the frame to the whole partition.
*/
SELECT
    c.Name AS Category,
    p.Name AS Product,
    p.UnitPrice,
    FIRST_VALUE(p.Name) OVER (PARTITION BY p.CategoryId ORDER BY p.UnitPrice DESC) AS MostExpensive,
    LAST_VALUE(p.Name)  OVER (PARTITION BY p.CategoryId ORDER BY p.UnitPrice DESC
                              ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS Cheapest
FROM dbo.Products AS p
INNER JOIN dbo.Categories AS c
    ON c.CategoryId = p.CategoryId
ORDER BY c.Name, p.UnitPrice DESC;
GO

/* Gaps and islands: group consecutive dates that had orders into streaks. */
WITH ActiveDays AS
(
    SELECT DISTINCT CAST(o.OrderDate AS DATE) AS [Date]
    FROM dbo.Orders AS o
    WHERE o.OrderDate >= DATEADD(DAY, -120, SYSUTCDATETIME())
),
Grouped AS
(
    SELECT
        [Date],
        DATEADD(DAY, -ROW_NUMBER() OVER (ORDER BY [Date]), [Date]) AS IslandKey
    FROM ActiveDays
)
SELECT
    MIN([Date])  AS StreakStart,
    MAX([Date])  AS StreakEnd,
    COUNT(*)     AS ConsecutiveDays
FROM Grouped
GROUP BY IslandKey
ORDER BY StreakStart;
GO

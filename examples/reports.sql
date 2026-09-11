/*
    Practical reports combining the techniques from the other folders.

    These are the shapes that show up in almost every business application.
*/

USE SqlRecipes;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ------------------------------------------------------------------------- */
/* Monthly revenue with growth against the previous month                     */
/* ------------------------------------------------------------------------- */
WITH MonthlyRevenue AS
(
    SELECT
        DATEFROMPARTS(YEAR(o.OrderDate), MONTH(o.OrderDate), 1) AS [Month],
        COUNT(*)                                                AS Orders,
        SUM(o.TotalAmount)                                      AS Revenue,
        COUNT(DISTINCT o.CustomerId)                            AS Customers
    FROM dbo.Orders AS o
    WHERE o.Status <> 'Cancelled'
    GROUP BY DATEFROMPARTS(YEAR(o.OrderDate), MONTH(o.OrderDate), 1)
)
SELECT
    [Month],
    Orders,
    Customers,
    Revenue,
    Revenue / NULLIF(Orders, 0)                                        AS AverageTicket,
    LAG(Revenue) OVER (ORDER BY [Month])                               AS PreviousMonth,
    CAST(100.0 * (Revenue - LAG(Revenue) OVER (ORDER BY [Month]))
         / NULLIF(LAG(Revenue) OVER (ORDER BY [Month]), 0)
         AS DECIMAL(8, 2))                                             AS GrowthPercent,
    SUM(Revenue) OVER (ORDER BY [Month] ROWS UNBOUNDED PRECEDING)      AS CumulativeRevenue
FROM MonthlyRevenue
ORDER BY [Month];
GO

/* ------------------------------------------------------------------------- */
/* Top 3 products per category by revenue                                     */
/* ------------------------------------------------------------------------- */
WITH ProductRevenue AS
(
    SELECT
        cat.CategoryId,
        cat.Name                                             AS Category,
        p.ProductId,
        p.Name                                               AS Product,
        SUM(oi.Quantity)                                     AS UnitsSold,
        SUM(oi.Quantity * oi.UnitPrice * (1 - oi.Discount))  AS Revenue
    FROM dbo.OrderItems AS oi
    INNER JOIN dbo.Orders AS o
        ON o.OrderId = oi.OrderId
    INNER JOIN dbo.Products AS p
        ON p.ProductId = oi.ProductId
    INNER JOIN dbo.Categories AS cat
        ON cat.CategoryId = p.CategoryId
    WHERE o.Status <> 'Cancelled'
    GROUP BY cat.CategoryId, cat.Name, p.ProductId, p.Name
),
Ranked AS
(
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY CategoryId ORDER BY Revenue DESC) AS RankInCategory,
        CAST(100.0 * Revenue / SUM(Revenue) OVER (PARTITION BY CategoryId) AS DECIMAL(5, 2)) AS PercentOfCategory
    FROM ProductRevenue
)
SELECT Category, RankInCategory, Product, UnitsSold, Revenue, PercentOfCategory
FROM Ranked
WHERE RankInCategory <= 3
ORDER BY Category, RankInCategory;
GO

/* ------------------------------------------------------------------------- */
/* RFM segmentation: Recency, Frequency, Monetary                             */
/* ------------------------------------------------------------------------- */
WITH CustomerStats AS
(
    SELECT
        c.CustomerId,
        c.FullName,
        c.State,
        DATEDIFF(DAY, MAX(o.OrderDate), SYSUTCDATETIME()) AS DaysSinceLastOrder,
        COUNT(*)                                          AS OrderCount,
        SUM(o.TotalAmount)                                AS Revenue
    FROM dbo.Customers AS c
    INNER JOIN dbo.Orders AS o
        ON o.CustomerId = c.CustomerId
    WHERE o.Status <> 'Cancelled'
    GROUP BY c.CustomerId, c.FullName, c.State
),
Scored AS
(
    SELECT
        *,
        NTILE(5) OVER (ORDER BY DaysSinceLastOrder DESC) AS RecencyScore,
        NTILE(5) OVER (ORDER BY OrderCount)              AS FrequencyScore,
        NTILE(5) OVER (ORDER BY Revenue)                 AS MonetaryScore
    FROM CustomerStats
)
SELECT TOP (25)
    FullName,
    State,
    DaysSinceLastOrder,
    OrderCount,
    Revenue,
    RecencyScore,
    FrequencyScore,
    MonetaryScore,
    CASE
        WHEN RecencyScore >= 4 AND FrequencyScore >= 4 AND MonetaryScore >= 4 THEN 'Champion'
        WHEN RecencyScore >= 4 AND FrequencyScore >= 3                        THEN 'Loyal'
        WHEN RecencyScore >= 4                                                THEN 'Promising'
        WHEN RecencyScore <= 2 AND MonetaryScore >= 4                         THEN 'At risk, high value'
        WHEN RecencyScore <= 2                                                THEN 'Churning'
        ELSE 'Needs attention'
    END AS Segment
FROM Scored
ORDER BY Revenue DESC;
GO

/* ------------------------------------------------------------------------- */
/* Monthly cohort retention                                                   */
/* ------------------------------------------------------------------------- */
WITH FirstOrder AS
(
    SELECT
        o.CustomerId,
        DATEFROMPARTS(YEAR(MIN(o.OrderDate)), MONTH(MIN(o.OrderDate)), 1) AS CohortMonth
    FROM dbo.Orders AS o
    WHERE o.Status <> 'Cancelled'
    GROUP BY o.CustomerId
),
Activity AS
(
    SELECT DISTINCT
        f.CohortMonth,
        f.CustomerId,
        DATEDIFF(MONTH, f.CohortMonth,
                 DATEFROMPARTS(YEAR(o.OrderDate), MONTH(o.OrderDate), 1)) AS MonthsSinceFirst
    FROM dbo.Orders AS o
    INNER JOIN FirstOrder AS f
        ON f.CustomerId = o.CustomerId
    WHERE o.Status <> 'Cancelled'
),
CohortSize AS
(
    SELECT CohortMonth, COUNT(DISTINCT CustomerId) AS Customers
    FROM FirstOrder
    GROUP BY CohortMonth
)
SELECT
    a.CohortMonth,
    s.Customers                                                        AS CohortSize,
    a.MonthsSinceFirst,
    COUNT(DISTINCT a.CustomerId)                                       AS ActiveCustomers,
    CAST(100.0 * COUNT(DISTINCT a.CustomerId) / s.Customers AS DECIMAL(5, 2)) AS RetentionPercent
FROM Activity AS a
INNER JOIN CohortSize AS s
    ON s.CohortMonth = a.CohortMonth
WHERE a.MonthsSinceFirst BETWEEN 0 AND 6
GROUP BY a.CohortMonth, s.Customers, a.MonthsSinceFirst
ORDER BY a.CohortMonth, a.MonthsSinceFirst;
GO

/* ------------------------------------------------------------------------- */
/* Daily sales including days with no activity                                */
/* ------------------------------------------------------------------------- */
/*
    A plain GROUP BY over Orders can only return days that had orders. The
    calendar CTE supplies the missing days so charts do not skip gaps.
*/
DECLARE @From DATE = DATEADD(DAY, -29, CAST(SYSUTCDATETIME() AS DATE));
DECLARE @To   DATE = CAST(SYSUTCDATETIME() AS DATE);

WITH Calendar AS
(
    SELECT @From AS [Date]
    UNION ALL
    SELECT DATEADD(DAY, 1, [Date]) FROM Calendar WHERE [Date] < @To
)
SELECT
    cal.[Date],
    DATENAME(WEEKDAY, cal.[Date])           AS DayOfWeek,
    COUNT(o.OrderId)                        AS Orders,
    ISNULL(SUM(o.TotalAmount), 0)           AS Revenue,
    AVG(COUNT(o.OrderId) * 1.0) OVER (ORDER BY cal.[Date] ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS SevenDayAverage
FROM Calendar AS cal
LEFT JOIN dbo.Orders AS o
    ON CAST(o.OrderDate AS DATE) = cal.[Date]
   AND o.Status <> 'Cancelled'
GROUP BY cal.[Date]
ORDER BY cal.[Date]
OPTION (MAXRECURSION 400);
GO

/* ------------------------------------------------------------------------- */
/* Inventory alert: products that will run out based on recent velocity       */
/* ------------------------------------------------------------------------- */
WITH RecentSales AS
(
    SELECT
        oi.ProductId,
        SUM(oi.Quantity) * 1.0 / 90 AS DailyVelocity
    FROM dbo.OrderItems AS oi
    INNER JOIN dbo.Orders AS o
        ON o.OrderId = oi.OrderId
    WHERE o.Status <> 'Cancelled'
      AND o.OrderDate >= DATEADD(DAY, -90, SYSUTCDATETIME())
    GROUP BY oi.ProductId
)
SELECT TOP (20)
    p.Name,
    c.Name                                                       AS Category,
    p.StockOnHand,
    CAST(r.DailyVelocity AS DECIMAL(10, 2))                      AS UnitsPerDay,
    CASE
        WHEN r.DailyVelocity > 0
        THEN CAST(p.StockOnHand / r.DailyVelocity AS INT)
    END                                                          AS DaysOfCoverRemaining
FROM dbo.Products AS p
INNER JOIN dbo.Categories AS c
    ON c.CategoryId = p.CategoryId
INNER JOIN RecentSales AS r
    ON r.ProductId = p.ProductId
WHERE p.IsActive = 1
  AND r.DailyVelocity > 0
ORDER BY DaysOfCoverRemaining;
GO

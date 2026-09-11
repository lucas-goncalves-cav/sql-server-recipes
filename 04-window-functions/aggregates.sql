/*
    Aggregate window functions: totals that keep the detail rows.
*/

USE SqlRecipes;
GO

/*
    GROUP BY collapses rows. OVER() keeps them and adds the aggregate
    alongside each row, which is what makes percent of total possible.
*/
SELECT TOP (30)
    c.Name                                        AS Category,
    p.Name                                        AS Product,
    p.UnitPrice,
    SUM(p.UnitPrice) OVER (PARTITION BY p.CategoryId)                       AS CategoryTotal,
    AVG(p.UnitPrice) OVER (PARTITION BY p.CategoryId)                       AS CategoryAverage,
    COUNT(*)         OVER (PARTITION BY p.CategoryId)                       AS ProductsInCategory,
    CAST(100.0 * p.UnitPrice / SUM(p.UnitPrice) OVER (PARTITION BY p.CategoryId) AS DECIMAL(5, 2)) AS PercentOfCategory
FROM dbo.Products AS p
INNER JOIN dbo.Categories AS c
    ON c.CategoryId = p.CategoryId
ORDER BY c.Name, p.UnitPrice DESC;
GO

/*
    Running total. Adding ORDER BY inside OVER turns the aggregate into a
    cumulative one over the frame that ends at the current row.
*/
WITH DailyRevenue AS
(
    SELECT
        CAST(o.OrderDate AS DATE) AS [Date],
        SUM(o.TotalAmount)        AS Revenue
    FROM dbo.Orders AS o
    WHERE o.Status <> 'Cancelled'
      AND o.OrderDate >= DATEADD(DAY, -60, SYSUTCDATETIME())
    GROUP BY CAST(o.OrderDate AS DATE)
)
SELECT
    [Date],
    Revenue,
    SUM(Revenue) OVER (ORDER BY [Date] ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningTotal,
    AVG(Revenue) OVER (ORDER BY [Date] ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)         AS SevenDayMovingAverage
FROM DailyRevenue
ORDER BY [Date];
GO

/*
    ROWS vs RANGE

    ROWS  counts physical rows, so a frame of "2 PRECEDING" is exactly two rows.
    RANGE works on values, so rows sharing the ORDER BY value belong to the same
    frame. With duplicates in the ordering column the two give different answers.

    The default frame when ORDER BY is present is
    RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW,
    which is usually slower than the ROWS equivalent. Be explicit.
*/
WITH DailyRevenue AS
(
    SELECT
        CAST(o.OrderDate AS DATE) AS [Date],
        SUM(o.TotalAmount)        AS Revenue
    FROM dbo.Orders AS o
    WHERE o.OrderDate >= DATEADD(DAY, -30, SYSUTCDATETIME())
    GROUP BY CAST(o.OrderDate AS DATE)
)
SELECT
    [Date],
    Revenue,
    SUM(Revenue) OVER (ORDER BY [Date] ROWS  BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS WithRows,
    SUM(Revenue) OVER (ORDER BY [Date] RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS WithRange
FROM DailyRevenue
ORDER BY [Date];
GO

/* A named window avoids repeating the same OVER clause. */
SELECT TOP (20)
    o.OrderNumber,
    o.OrderDate,
    o.TotalAmount,
    SUM(o.TotalAmount) OVER w AS RunningTotal,
    AVG(o.TotalAmount) OVER w AS RunningAverage
FROM dbo.Orders AS o
WHERE o.CustomerId = 1
WINDOW w AS (ORDER BY o.OrderDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
ORDER BY o.OrderDate;
GO

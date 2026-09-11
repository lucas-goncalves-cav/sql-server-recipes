/*
    Ranking window functions: ROW_NUMBER, RANK, DENSE_RANK, NTILE.
*/

USE SqlRecipes;
GO

/*
    The three ranking functions differ only in how they handle ties.

    Values:      100  100   90   80
    ROW_NUMBER:    1    2    3    4   always unique
    RANK:          1    1    3    4   ties share, next value skips
    DENSE_RANK:    1    1    2    3   ties share, no gap
*/
SELECT TOP (20)
    p.Name,
    p.UnitPrice,
    ROW_NUMBER() OVER (ORDER BY p.UnitPrice DESC) AS RowNumber,
    RANK()       OVER (ORDER BY p.UnitPrice DESC) AS Rank,
    DENSE_RANK() OVER (ORDER BY p.UnitPrice DESC) AS DenseRank
FROM dbo.Products AS p
ORDER BY p.UnitPrice DESC;
GO

/* PARTITION BY restarts the numbering for each group. */
SELECT
    c.Name AS Category,
    p.Name AS Product,
    p.UnitPrice,
    ROW_NUMBER() OVER (PARTITION BY p.CategoryId ORDER BY p.UnitPrice DESC) AS PriceRankInCategory
FROM dbo.Products AS p
INNER JOIN dbo.Categories AS c
    ON c.CategoryId = p.CategoryId
ORDER BY c.Name, PriceRankInCategory;
GO

/*
    Top N per group. A window function cannot be used in WHERE, because WHERE
    runs before SELECT. Wrap it in a CTE or derived table.
*/
WITH Ranked AS
(
    SELECT
        c.Name AS Category,
        p.Name AS Product,
        p.UnitPrice,
        ROW_NUMBER() OVER (PARTITION BY p.CategoryId ORDER BY p.UnitPrice DESC) AS rn
    FROM dbo.Products AS p
    INNER JOIN dbo.Categories AS c
        ON c.CategoryId = p.CategoryId
)
SELECT Category, Product, UnitPrice
FROM Ranked
WHERE rn <= 3
ORDER BY Category, UnitPrice DESC;
GO

/* Deduplication: keep one row per key and delete the rest. */
WITH Duplicates AS
(
    SELECT
        oi.OrderItemId,
        ROW_NUMBER() OVER (PARTITION BY oi.OrderId, oi.ProductId ORDER BY oi.OrderItemId) AS rn
    FROM dbo.OrderItems AS oi
)
SELECT COUNT(*) AS DuplicateRows
FROM Duplicates
WHERE rn > 1;
GO

/* NTILE splits the ordered set into N buckets of roughly equal size. */
SELECT
    c.FullName,
    revenue.Total,
    NTILE(4) OVER (ORDER BY revenue.Total DESC) AS RevenueQuartile
FROM dbo.Customers AS c
INNER JOIN
(
    SELECT o.CustomerId, SUM(o.TotalAmount) AS Total
    FROM dbo.Orders AS o
    WHERE o.Status <> 'Cancelled'
    GROUP BY o.CustomerId
) AS revenue
    ON revenue.CustomerId = c.CustomerId
ORDER BY revenue.Total DESC;
GO

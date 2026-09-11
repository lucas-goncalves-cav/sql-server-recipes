/*
    SELECT: projection, aliases, DISTINCT, TOP and computed columns.
*/

USE SqlRecipes;
GO

/* Name the columns you need. SELECT * couples the query to the table shape. */
SELECT
    p.ProductId,
    p.Name,
    p.UnitPrice
FROM dbo.Products AS p;
GO

/* Aliases keep the result readable for whoever consumes it. */
SELECT
    p.Name       AS ProductName,
    p.UnitPrice  AS Price,
    p.StockOnHand AS Stock
FROM dbo.Products AS p;
GO

/* Computed columns are evaluated per row. */
SELECT
    p.Name,
    p.UnitPrice,
    p.StockOnHand,
    p.UnitPrice * p.StockOnHand AS InventoryValue
FROM dbo.Products AS p
WHERE p.IsActive = 1;
GO

/* DISTINCT removes duplicate rows from the result, not from the table. */
SELECT DISTINCT c.State
FROM dbo.Customers AS c;
GO

/* TOP without ORDER BY is non deterministic. Always pair them. */
SELECT TOP (10)
    p.Name,
    p.UnitPrice
FROM dbo.Products AS p
ORDER BY p.UnitPrice DESC;
GO

/* TOP WITH TIES returns every row that matches the last ordered value. */
SELECT TOP (5) WITH TIES
    p.Name,
    p.CategoryId
FROM dbo.Products AS p
ORDER BY p.CategoryId;
GO

/* CASE turns a stored value into a presentation label. */
SELECT
    o.OrderNumber,
    o.TotalAmount,
    CASE
        WHEN o.TotalAmount >= 3000 THEN 'High'
        WHEN o.TotalAmount >= 1000 THEN 'Medium'
        ELSE 'Low'
    END AS AmountTier
FROM dbo.Orders AS o
ORDER BY o.TotalAmount DESC;
GO

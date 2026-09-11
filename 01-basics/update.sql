/*
    UPDATE: filtered updates, updates driven by a join, and OUTPUT.
*/

USE SqlRecipes;
GO

/* An UPDATE without WHERE touches every row. Write the WHERE clause first. */
UPDATE dbo.Products
SET UnitPrice = UnitPrice * 1.10
WHERE CategoryId = 1
  AND IsActive = 1;

SELECT @@ROWCOUNT AS RowsAffected;
GO

/* UPDATE with a join: the UPDATE targets the alias, not the table name. */
UPDATE p
SET p.StockOnHand = p.StockOnHand + 50
FROM dbo.Products AS p
INNER JOIN dbo.Categories AS c
    ON c.CategoryId = p.CategoryId
WHERE c.Name = N'Books';
GO

/* OUTPUT exposes both the old and the new value, which makes auditing trivial. */
DECLARE @PriceChanges TABLE
(
    ProductId INT,
    OldPrice  DECIMAL(18, 2),
    NewPrice  DECIMAL(18, 2)
);

UPDATE dbo.Products
SET UnitPrice = UnitPrice * 0.95
OUTPUT inserted.ProductId, deleted.UnitPrice, inserted.UnitPrice INTO @PriceChanges
WHERE UnitPrice > 1200.00;

SELECT TOP (10) * FROM @PriceChanges;
GO

/* Updating from an aggregate: recalculate order totals from their items. */
UPDATE o
SET o.TotalAmount = totals.Amount
FROM dbo.Orders AS o
INNER JOIN
(
    SELECT
        oi.OrderId,
        SUM(oi.Quantity * oi.UnitPrice * (1 - oi.Discount)) AS Amount
    FROM dbo.OrderItems AS oi
    GROUP BY oi.OrderId
) AS totals
    ON totals.OrderId = o.OrderId;

SELECT @@ROWCOUNT AS OrdersRecalculated;
GO

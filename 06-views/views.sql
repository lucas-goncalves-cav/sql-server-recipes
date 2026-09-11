/*
    Views: naming a query so callers do not repeat it.
*/

USE SqlRecipes;
GO

/*
    Indexed views require these SET options to be ON at creation time and for
    every session that writes to the base tables. sqlcmd leaves QUOTED_IDENTIFIER
    off by default, which is why it is set explicitly here.
*/
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

DROP VIEW IF EXISTS dbo.vw_OrderSummary;
GO

CREATE VIEW dbo.vw_OrderSummary
AS
SELECT
    o.OrderId,
    o.OrderNumber,
    o.Status,
    o.OrderDate,
    c.CustomerId,
    c.FullName    AS CustomerName,
    c.State,
    o.TotalAmount,
    itemCount.Items
FROM dbo.Orders AS o
INNER JOIN dbo.Customers AS c
    ON c.CustomerId = o.CustomerId
CROSS APPLY
(
    SELECT COUNT(*) AS Items
    FROM dbo.OrderItems AS oi
    WHERE oi.OrderId = o.OrderId
) AS itemCount;
GO

SELECT TOP (10) * FROM dbo.vw_OrderSummary ORDER BY OrderDate DESC;
GO

/* A view can be filtered and joined like any table. */
SELECT
    State,
    COUNT(*)          AS Orders,
    SUM(TotalAmount)  AS Revenue
FROM dbo.vw_OrderSummary
WHERE Status = 'Delivered'
GROUP BY State
ORDER BY Revenue DESC;
GO

/*
    WITH SCHEMABINDING ties the view to the columns it reads. Dropping or
    altering them then fails instead of silently breaking the view.
    It is also a prerequisite for an indexed view.
*/
DROP VIEW IF EXISTS dbo.vw_ProductCatalog;
GO

CREATE VIEW dbo.vw_ProductCatalog
WITH SCHEMABINDING
AS
SELECT
    p.ProductId,
    p.Name,
    p.Sku,
    p.UnitPrice,
    p.CategoryId,
    c.Name AS CategoryName
FROM dbo.Products AS p
INNER JOIN dbo.Categories AS c
    ON c.CategoryId = p.CategoryId
WHERE p.IsActive = 1;
GO

SELECT TOP (10) * FROM dbo.vw_ProductCatalog;
GO

/*
    An indexed view materializes the result on disk and keeps it in sync.
    Requirements: SCHEMABINDING, two part names, COUNT_BIG(*) when aggregating,
    no outer joins, no subqueries, and a unique clustered index.

    It speeds up reads and slows down every write to the base tables, so it
    pays off only when the aggregate is read far more often than it changes.
*/
DROP VIEW IF EXISTS dbo.vw_CategorySales;
GO

CREATE VIEW dbo.vw_CategorySales
WITH SCHEMABINDING
AS
SELECT
    p.CategoryId,
    COUNT_BIG(*)         AS LineCount,
    SUM(oi.Quantity)     AS UnitsSold
FROM dbo.OrderItems AS oi
INNER JOIN dbo.Products AS p
    ON p.ProductId = oi.ProductId
GROUP BY p.CategoryId;
GO

CREATE UNIQUE CLUSTERED INDEX IX_vw_CategorySales
    ON dbo.vw_CategorySales (CategoryId);
GO

SELECT * FROM dbo.vw_CategorySales ORDER BY UnitsSold DESC;
GO

/*
    WITH CHECK OPTION blocks writes through the view that would produce a row
    the view itself cannot see.
*/
DROP VIEW IF EXISTS dbo.vw_ActiveCategories;
GO

CREATE VIEW dbo.vw_ActiveCategories
AS
SELECT CategoryId, Name, Description, IsActive
FROM dbo.Categories
WHERE IsActive = 1
WITH CHECK OPTION;
GO

/* Allowed: the new row satisfies the view predicate. */
INSERT INTO dbo.vw_ActiveCategories (Name, Description, IsActive)
VALUES (N'Temporary Category', N'Created through the view', 1);

/* Rejected by WITH CHECK OPTION: IsActive = 0 would fall outside the view. */
BEGIN TRY
    INSERT INTO dbo.vw_ActiveCategories (Name, Description, IsActive)
    VALUES (N'Invisible Category', N'Should be rejected', 0);
END TRY
BEGIN CATCH
    PRINT 'Rejected as expected: ' + ERROR_MESSAGE();
END CATCH;
GO

DELETE FROM dbo.Categories WHERE Name = N'Temporary Category';
GO

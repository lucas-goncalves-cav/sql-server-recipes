/*
    Triggers: auditing and enforcing rules that constraints cannot express.

    The single most important rule: a trigger fires once per statement, not
    once per row. The inserted and deleted pseudo tables can hold many rows.
*/

USE SqlRecipes;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

DROP TABLE IF EXISTS dbo.ProductPriceAudit;
GO

CREATE TABLE dbo.ProductPriceAudit
(
    AuditId    INT IDENTITY(1, 1) NOT NULL,
    ProductId  INT                NOT NULL,
    OldPrice   DECIMAL(18, 2)     NULL,
    NewPrice   DECIMAL(18, 2)     NULL,
    Action     VARCHAR(10)        NOT NULL,
    ChangedBy  SYSNAME            NOT NULL CONSTRAINT DF_PriceAudit_ChangedBy DEFAULT (SUSER_SNAME()),
    ChangedAt  DATETIME2(3)       NOT NULL CONSTRAINT DF_PriceAudit_ChangedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_ProductPriceAudit PRIMARY KEY CLUSTERED (AuditId)
);
GO

/* ------------------------------------------------------------------------- */
/* AFTER trigger: audit price changes, set based.                             */
/* ------------------------------------------------------------------------- */
DROP TRIGGER IF EXISTS dbo.tr_Products_AuditPrice;
GO

CREATE TRIGGER dbo.tr_Products_AuditPrice
ON dbo.Products
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    /* Nothing changed, nothing to do. Saves work on no-op statements. */
    IF NOT EXISTS (SELECT 1 FROM inserted) AND NOT EXISTS (SELECT 1 FROM deleted)
        RETURN;

    /*
        UPDATE() reports whether the column appeared in the SET list, not
        whether the value actually changed. The join below handles the rest.
    */
    INSERT INTO dbo.ProductPriceAudit (ProductId, OldPrice, NewPrice, Action)
    SELECT
        COALESCE(i.ProductId, d.ProductId),
        d.UnitPrice,
        i.UnitPrice,
        CASE
            WHEN i.ProductId IS NOT NULL AND d.ProductId IS NOT NULL THEN 'UPDATE'
            WHEN i.ProductId IS NOT NULL                             THEN 'INSERT'
            ELSE 'DELETE'
        END
    FROM inserted AS i
    FULL JOIN deleted AS d
        ON d.ProductId = i.ProductId
    WHERE i.ProductId IS NULL                      -- delete
       OR d.ProductId IS NULL                      -- insert
       OR i.UnitPrice <> d.UnitPrice;              -- genuine price change
END;
GO

/* A multi row update produces one audit row per affected product. */
UPDATE dbo.Products
SET UnitPrice = UnitPrice * 1.05
WHERE CategoryId = 2;

SELECT TOP (10)
    ProductId,
    OldPrice,
    NewPrice,
    Action,
    ChangedAt
FROM dbo.ProductPriceAudit
ORDER BY AuditId DESC;

SELECT COUNT(*) AS AuditRowsFromOneStatement FROM dbo.ProductPriceAudit;
GO

/* ------------------------------------------------------------------------- */
/* INSTEAD OF trigger: make a non updatable view updatable.                   */
/* ------------------------------------------------------------------------- */
DROP VIEW IF EXISTS dbo.vw_ProductWithCategory;
GO

CREATE VIEW dbo.vw_ProductWithCategory
AS
SELECT
    p.ProductId,
    p.Name,
    p.UnitPrice,
    c.Name AS CategoryName
FROM dbo.Products AS p
INNER JOIN dbo.Categories AS c
    ON c.CategoryId = p.CategoryId;
GO

/* A view spanning two tables cannot be updated directly. This makes it work. */
DROP TRIGGER IF EXISTS dbo.tr_vw_ProductWithCategory_Update;
GO

CREATE TRIGGER dbo.tr_vw_ProductWithCategory_Update
ON dbo.vw_ProductWithCategory
INSTEAD OF UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE p
    SET p.Name       = i.Name,
        p.UnitPrice  = i.UnitPrice,
        p.CategoryId = c.CategoryId
    FROM dbo.Products AS p
    INNER JOIN inserted AS i
        ON i.ProductId = p.ProductId
    INNER JOIN dbo.Categories AS c
        ON c.Name = i.CategoryName;
END;
GO

UPDATE dbo.vw_ProductWithCategory
SET CategoryName = N'Books'
WHERE ProductId = 1;

SELECT ProductId, Name, CategoryName
FROM dbo.vw_ProductWithCategory
WHERE ProductId = 1;
GO

/* ------------------------------------------------------------------------- */
/* A rule a CHECK constraint cannot express: it spans another table.          */
/* ------------------------------------------------------------------------- */
DROP TRIGGER IF EXISTS dbo.tr_OrderItems_BlockInactiveProducts;
GO

CREATE TRIGGER dbo.tr_OrderItems_BlockInactiveProducts
ON dbo.OrderItems
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS
    (
        SELECT 1
        FROM inserted AS i
        INNER JOIN dbo.Products AS p
            ON p.ProductId = i.ProductId
        WHERE p.IsActive = 0
    )
    BEGIN
        /*
            THROW inside a trigger rolls the statement back. XACT_ABORT is
            implicitly on for triggers, so the whole transaction is undone.
        */
        THROW 50100, 'An order item cannot reference an inactive product.', 1;
    END;
END;
GO

DECLARE @InactiveProductId INT = (SELECT TOP (1) ProductId FROM dbo.Products WHERE IsActive = 0);

BEGIN TRY
    INSERT INTO dbo.OrderItems (OrderId, ProductId, Quantity, UnitPrice, Discount)
    VALUES (1, @InactiveProductId, 1, 10.00, 0);
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
END CATCH;
GO

/* ------------------------------------------------------------------------- */
/* Cleanup                                                                    */
/* ------------------------------------------------------------------------- */
DROP TRIGGER IF EXISTS dbo.tr_OrderItems_BlockInactiveProducts;
DROP TRIGGER IF EXISTS dbo.tr_Products_AuditPrice;
GO

/*
    BAD: comparing a VARCHAR column to an NVARCHAR parameter.

    Data type precedence promotes VARCHAR to NVARCHAR, so the conversion lands
    on the COLUMN side. That makes the predicate non sargable exactly the same
    way a function would, and the plan shows a CONVERT_IMPLICIT warning.

    This is one of the most common causes of a slow query in applications using
    an ORM that sends every string as NVARCHAR.
*/

USE SqlRecipes;
GO

CREATE NONCLUSTERED INDEX IX_Products_Sku ON dbo.Products (Sku) INCLUDE (Name, UnitPrice);
GO

SET STATISTICS IO ON;

DECLARE @Sku NVARCHAR(32) = N'SKU-0042';

SELECT p.ProductId, p.Name, p.UnitPrice
FROM dbo.Products AS p
WHERE p.Sku = @Sku;

SET STATISTICS IO OFF;
GO

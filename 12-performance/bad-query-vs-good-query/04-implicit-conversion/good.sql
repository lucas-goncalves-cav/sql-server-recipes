/*
    GOOD: the parameter type matches the column type.

    No conversion is needed on the column side, so the index seeks.

    The fix belongs on both ends: declare the parameter as VARCHAR here, and
    in the application tell the driver the column is non Unicode. In .NET that
    is SqlDbType.VarChar rather than the NVarChar default.
*/

USE SqlRecipes;
GO

SET STATISTICS IO ON;

DECLARE @Sku VARCHAR(32) = 'SKU-0042';

SELECT p.ProductId, p.Name, p.UnitPrice
FROM dbo.Products AS p
WHERE p.Sku = @Sku;

SET STATISTICS IO OFF;
GO

DROP INDEX IF EXISTS IX_Products_Sku ON dbo.Products;
GO

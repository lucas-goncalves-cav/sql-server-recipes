/*
    Pagination with OFFSET / FETCH.
*/

USE SqlRecipes;
GO

DECLARE @Page     INT = 3;
DECLARE @PageSize INT = 20;

/* ORDER BY is mandatory. Without it the page contents are undefined. */
SELECT
    p.ProductId,
    p.Name,
    p.UnitPrice
FROM dbo.Products AS p
ORDER BY p.Name
OFFSET (@Page - 1) * @PageSize ROWS
FETCH NEXT @PageSize ROWS ONLY;
GO

/*
    Add a tiebreaker to the sort. Without a unique column in ORDER BY, rows
    sharing the sort value can appear on two pages or on none.
*/
DECLARE @Page     INT = 2;
DECLARE @PageSize INT = 10;

SELECT
    p.ProductId,
    p.Name,
    p.CategoryId
FROM dbo.Products AS p
ORDER BY p.CategoryId, p.ProductId    -- ProductId breaks the tie deterministically
OFFSET (@Page - 1) * @PageSize ROWS
FETCH NEXT @PageSize ROWS ONLY;
GO

/*
    Returning the total count. COUNT(*) OVER() gives the row count in the same
    pass, avoiding a second query, at the cost of carrying it on every row.
*/
DECLARE @Page     INT = 1;
DECLARE @PageSize INT = 20;

SELECT
    p.ProductId,
    p.Name,
    p.UnitPrice,
    COUNT(*) OVER () AS TotalRows
FROM dbo.Products AS p
WHERE p.IsActive = 1
ORDER BY p.Name
OFFSET (@Page - 1) * @PageSize ROWS
FETCH NEXT @PageSize ROWS ONLY;
GO

/* Filters and pagination combined in a single reusable shape. */
DECLARE @Search     NVARCHAR(100) = N'Product 1';
DECLARE @CategoryId INT           = NULL;
DECLARE @Page       INT           = 1;
DECLARE @PageSize   INT           = 15;

SELECT
    p.ProductId,
    p.Name,
    c.Name AS Category,
    p.UnitPrice,
    COUNT(*) OVER () AS TotalRows
FROM dbo.Products AS p
INNER JOIN dbo.Categories AS c
    ON c.CategoryId = p.CategoryId
WHERE (@Search IS NULL OR p.Name LIKE @Search + N'%')
  AND (@CategoryId IS NULL OR p.CategoryId = @CategoryId)
ORDER BY p.Name, p.ProductId
OFFSET (@Page - 1) * @PageSize ROWS
FETCH NEXT @PageSize ROWS ONLY;
GO

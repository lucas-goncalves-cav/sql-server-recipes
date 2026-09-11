/*
    Keyset pagination, also called seek method or cursor pagination.

    OFFSET makes the server read and discard every skipped row, so page 5000 is
    far slower than page 1. Keyset pagination remembers where the previous page
    ended and seeks straight to it, so every page costs the same.
*/

USE SqlRecipes;
GO

/* First page: no anchor yet. */
DECLARE @PageSize INT = 20;

SELECT TOP (@PageSize)
    o.OrderId,
    o.OrderNumber,
    o.OrderDate,
    o.TotalAmount
FROM dbo.Orders AS o
ORDER BY o.OrderId;
GO

/* Next page: start after the last key of the previous page. */
DECLARE @PageSize  INT = 20;
DECLARE @LastKey   INT = 20;

SELECT TOP (@PageSize)
    o.OrderId,
    o.OrderNumber,
    o.OrderDate,
    o.TotalAmount
FROM dbo.Orders AS o
WHERE o.OrderId > @LastKey
ORDER BY o.OrderId;
GO

/*
    Composite keyset. When ordering by a non unique column, the anchor needs
    both the sort column and a unique tiebreaker, compared as a tuple.
*/
DECLARE @PageSize      INT          = 20;
DECLARE @LastOrderDate DATETIME2(3) = '2026-01-15T00:00:00';
DECLARE @LastOrderId   INT          = 500;

SELECT TOP (@PageSize)
    o.OrderId,
    o.OrderNumber,
    o.OrderDate
FROM dbo.Orders AS o
WHERE (o.OrderDate > @LastOrderDate)
   OR (o.OrderDate = @LastOrderDate AND o.OrderId > @LastOrderId)
ORDER BY o.OrderDate, o.OrderId;
GO

/*
    Cost comparison. Run both with SET STATISTICS IO ON and compare the reads:
    the OFFSET version grows with the page number, the keyset version does not.
*/
SET STATISTICS IO ON;

PRINT 'OFFSET, page 500';
SELECT o.OrderId, o.OrderNumber
FROM dbo.Orders AS o
ORDER BY o.OrderId
OFFSET 9980 ROWS FETCH NEXT 20 ROWS ONLY;

PRINT 'KEYSET, equivalent position';
SELECT TOP (20) o.OrderId, o.OrderNumber
FROM dbo.Orders AS o
WHERE o.OrderId > 9980
ORDER BY o.OrderId;

SET STATISTICS IO OFF;
GO

/*
    Trade off

    OFFSET / FETCH
        + Can jump to an arbitrary page number
        + Trivial to implement
        - Cost grows linearly with the offset
        - Rows inserted or deleted between requests shift the pages

    Keyset
        + Constant cost regardless of depth
        + Stable while the underlying data changes
        - Only next and previous, no jumping to page N
        - Requires a unique, ordered anchor
*/

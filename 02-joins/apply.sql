/*
    CROSS APPLY and OUTER APPLY: a join where the right side depends on the left.
*/

USE SqlRecipes;
GO

/*
    A plain JOIN cannot reference the left table inside a derived table.
    APPLY can, which makes "top N per group" a one liner.
*/
SELECT
    c.FullName,
    recent.OrderNumber,
    recent.OrderDate,
    recent.TotalAmount
FROM dbo.Customers AS c
CROSS APPLY
(
    SELECT TOP (3)
        o.OrderNumber,
        o.OrderDate,
        o.TotalAmount
    FROM dbo.Orders AS o
    WHERE o.CustomerId = c.CustomerId
    ORDER BY o.OrderDate DESC
) AS recent;
GO

/* OUTER APPLY keeps the left row even when the right side returns nothing. */
SELECT
    c.FullName,
    lastOrder.OrderNumber,
    lastOrder.OrderDate
FROM dbo.Customers AS c
OUTER APPLY
(
    SELECT TOP (1)
        o.OrderNumber,
        o.OrderDate
    FROM dbo.Orders AS o
    WHERE o.CustomerId = c.CustomerId
    ORDER BY o.OrderDate DESC
) AS lastOrder;
GO

/* APPLY over VALUES unpivots columns into rows. */
SELECT
    o.OrderNumber,
    dates.Label,
    dates.Value
FROM dbo.Orders AS o
CROSS APPLY (VALUES
    ('Ordered', o.OrderDate),
    ('Shipped', o.ShippedDate)
) AS dates (Label, Value)
WHERE dates.Value IS NOT NULL;
GO

/* APPLY is also a clean way to reuse a computed expression. */
SELECT
    oi.OrderItemId,
    oi.Quantity,
    oi.UnitPrice,
    calc.LineTotal,
    calc.LineTotal * 0.18 AS EstimatedTax
FROM dbo.OrderItems AS oi
CROSS APPLY (VALUES (oi.Quantity * oi.UnitPrice * (1 - oi.Discount))) AS calc (LineTotal);
GO

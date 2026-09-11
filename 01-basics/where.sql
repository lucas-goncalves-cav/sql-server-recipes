/*
    WHERE: filtering rows before aggregation and projection.
*/

USE SqlRecipes;
GO

/* Comparison operators. */
SELECT p.Name, p.UnitPrice
FROM dbo.Products AS p
WHERE p.UnitPrice > 500.00;
GO

/* BETWEEN is inclusive on both ends. */
SELECT p.Name, p.UnitPrice
FROM dbo.Products AS p
WHERE p.UnitPrice BETWEEN 100.00 AND 300.00;
GO

/* IN is shorter and clearer than a chain of ORs. */
SELECT o.OrderNumber, o.Status
FROM dbo.Orders AS o
WHERE o.Status IN ('Paid', 'Shipped', 'Delivered');
GO

/* LIKE with a leading wildcard cannot use an index seek. */
SELECT c.FullName, c.Email
FROM dbo.Customers AS c
WHERE c.Email LIKE 'customer1%';
GO

/*
    NULL comparisons never evaluate to true.
    ShippedDate = NULL matches nothing. IS NULL is the only correct form.
*/
SELECT o.OrderNumber, o.Status
FROM dbo.Orders AS o
WHERE o.ShippedDate IS NULL;
GO

SELECT o.OrderNumber, o.ShippedDate
FROM dbo.Orders AS o
WHERE o.ShippedDate IS NOT NULL;
GO

/* Date ranges: half open intervals avoid time component surprises. */
DECLARE @Start DATETIME2(3) = DATEADD(DAY, -30, SYSUTCDATETIME());
DECLARE @End   DATETIME2(3) = SYSUTCDATETIME();

SELECT o.OrderNumber, o.OrderDate, o.TotalAmount
FROM dbo.Orders AS o
WHERE o.OrderDate >= @Start
  AND o.OrderDate <  @End;
GO

/* EXISTS stops at the first match and does not materialize a result set. */
SELECT c.CustomerId, c.FullName
FROM dbo.Customers AS c
WHERE EXISTS
(
    SELECT 1
    FROM dbo.Orders AS o
    WHERE o.CustomerId = c.CustomerId
      AND o.Status = 'Delivered'
);
GO

/* NOT IN with a nullable column returns nothing. NOT EXISTS is the safe form. */
SELECT c.CustomerId, c.FullName
FROM dbo.Customers AS c
WHERE NOT EXISTS
(
    SELECT 1
    FROM dbo.Orders AS o
    WHERE o.CustomerId = c.CustomerId
);
GO

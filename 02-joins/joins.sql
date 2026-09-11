/*
    JOIN types and what each one keeps.
*/

USE SqlRecipes;
GO

/* INNER JOIN: only rows that match on both sides. */
SELECT
    o.OrderNumber,
    c.FullName,
    o.TotalAmount
FROM dbo.Orders AS o
INNER JOIN dbo.Customers AS c
    ON c.CustomerId = o.CustomerId;
GO

/* LEFT JOIN: every customer, with order columns as NULL when there is no match. */
SELECT
    c.FullName,
    o.OrderNumber,
    o.TotalAmount
FROM dbo.Customers AS c
LEFT JOIN dbo.Orders AS o
    ON o.CustomerId = c.CustomerId;
GO

/* The anti join pattern: rows on the left with nothing on the right. */
SELECT c.CustomerId, c.FullName
FROM dbo.Customers AS c
LEFT JOIN dbo.Orders AS o
    ON o.CustomerId = c.CustomerId
WHERE o.OrderId IS NULL;
GO

/* RIGHT JOIN is a LEFT JOIN with the tables swapped. Prefer LEFT for readability. */
SELECT
    c.FullName,
    o.OrderNumber
FROM dbo.Orders AS o
RIGHT JOIN dbo.Customers AS c
    ON c.CustomerId = o.CustomerId;
GO

/* FULL JOIN: everything from both sides, NULL where there is no counterpart. */
SELECT
    c.CustomerId,
    c.FullName,
    o.OrderId
FROM dbo.Customers AS c
FULL JOIN dbo.Orders AS o
    ON o.CustomerId = c.CustomerId
WHERE c.CustomerId IS NULL
   OR o.OrderId IS NULL;
GO

/* CROSS JOIN: the Cartesian product. Useful to build calendars or matrices. */
SELECT
    c.Name AS Category,
    s.Status
FROM dbo.Categories AS c
CROSS JOIN (VALUES ('Pending'), ('Paid'), ('Shipped')) AS s (Status);
GO

/* Self join: pair each employee with their manager. */
SELECT
    e.FullName     AS Employee,
    e.JobTitle,
    m.FullName     AS Manager
FROM dbo.Employees AS e
LEFT JOIN dbo.Employees AS m
    ON m.EmployeeId = e.ManagerId
ORDER BY m.FullName, e.FullName;
GO

/* Multi table join with aggregation. */
SELECT
    cat.Name                                              AS Category,
    COUNT(DISTINCT o.OrderId)                             AS Orders,
    SUM(oi.Quantity)                                      AS UnitsSold,
    SUM(oi.Quantity * oi.UnitPrice * (1 - oi.Discount))   AS Revenue
FROM dbo.OrderItems AS oi
INNER JOIN dbo.Orders AS o
    ON o.OrderId = oi.OrderId
INNER JOIN dbo.Products AS p
    ON p.ProductId = oi.ProductId
INNER JOIN dbo.Categories AS cat
    ON cat.CategoryId = p.CategoryId
WHERE o.Status IN ('Paid', 'Shipped', 'Delivered')
GROUP BY cat.Name
ORDER BY Revenue DESC;
GO

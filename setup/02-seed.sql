/*
    Seeds the sample schema with enough volume to make index and performance
    examples meaningful: 5 categories, 200 products, 2,000 customers,
    ~20,000 orders and ~55,000 order items.

    Run 01-schema.sql first.
*/

USE SqlRecipes;
GO

SET NOCOUNT ON;
GO

INSERT INTO dbo.Categories (Name, Description)
VALUES
    (N'Electronics', N'Devices, gadgets and accessories'),
    (N'Books',       N'Printed and digital books'),
    (N'Furniture',   N'Home and office furniture'),
    (N'Apparel',     N'Clothing and footwear'),
    (N'Sports',      N'Sporting goods and equipment');
GO

/* Products: 200 rows spread across the five categories. */
WITH Numbers AS
(
    SELECT TOP (200) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects
)
INSERT INTO dbo.Products (CategoryId, Name, Sku, UnitPrice, StockOnHand, IsActive)
SELECT
    ((n - 1) % 5) + 1,
    CONCAT(N'Product ', RIGHT(CONCAT('000', n), 3)),
    CONCAT('SKU-', RIGHT(CONCAT('000', n), 4)),
    CAST(19.90 + (n * 7.35) AS DECIMAL(18, 2)),
    (n * 13) % 400,
    CASE WHEN n % 17 = 0 THEN 0 ELSE 1 END
FROM Numbers;
GO

/* Customers: 2,000 rows across a handful of cities. */
WITH Numbers AS
(
    SELECT TOP (2000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects a
    CROSS JOIN sys.all_objects b
)
INSERT INTO dbo.Customers (FullName, Email, City, State, CreatedAt)
SELECT
    CONCAT(N'Customer ', RIGHT(CONCAT('0000', n), 4)),
    CONCAT('customer', n, '@example.com'),
    CHOOSE(((n - 1) % 6) + 1, N'Sao Paulo', N'Rio de Janeiro', N'Belo Horizonte', N'Curitiba', N'Porto Alegre', N'Recife'),
    CHOOSE(((n - 1) % 6) + 1, 'SP', 'RJ', 'MG', 'PR', 'RS', 'PE'),
    DATEADD(DAY, -((n * 3) % 900), SYSUTCDATETIME())
FROM Numbers;
GO

/* Orders: 20,000 rows over the last two years. */
WITH Numbers AS
(
    SELECT TOP (20000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects a
    CROSS JOIN sys.all_objects b
)
INSERT INTO dbo.Orders (CustomerId, OrderNumber, Status, OrderDate, ShippedDate, TotalAmount)
SELECT
    ((n - 1) % 2000) + 1,
    CONCAT('ORD-', RIGHT(CONCAT('00000', n), 6)),
    CHOOSE(((n - 1) % 5) + 1, 'Pending', 'Paid', 'Shipped', 'Delivered', 'Cancelled'),
    DATEADD(HOUR, -((n * 7) % 17520), SYSUTCDATETIME()),
    CASE
        WHEN ((n - 1) % 5) + 1 IN (3, 4)
            THEN DATEADD(HOUR, -((n * 7) % 17520) + 48, SYSUTCDATETIME())
        ELSE NULL
    END,
    CAST(50 + ((n * 13) % 4500) AS DECIMAL(18, 2))
FROM Numbers;
GO

/* Order items: between 1 and 3 rows per order. */
INSERT INTO dbo.OrderItems (OrderId, ProductId, Quantity, UnitPrice, Discount)
SELECT
    o.OrderId,
    ((o.OrderId + i.Offset) % 200) + 1,
    ((o.OrderId + i.Offset) % 4) + 1,
    p.UnitPrice,
    CASE WHEN (o.OrderId + i.Offset) % 11 = 0 THEN 0.1000 ELSE 0 END
FROM dbo.Orders AS o
CROSS APPLY (VALUES (0), (37), (91)) AS i (Offset)
INNER JOIN dbo.Products AS p
    ON p.ProductId = ((o.OrderId + i.Offset) % 200) + 1
WHERE i.Offset = 0
   OR (o.OrderId % 3 = 0 AND i.Offset = 37)
   OR (o.OrderId % 5 = 0 AND i.Offset = 91);
GO

/* Employees: a four level hierarchy for the recursive CTE examples. */
INSERT INTO dbo.Employees (ManagerId, FullName, JobTitle, Salary, HiredAt)
VALUES (NULL, N'Helena Prado', N'Chief Executive Officer', 42000.00, '2016-02-01');

INSERT INTO dbo.Employees (ManagerId, FullName, JobTitle, Salary, HiredAt)
VALUES
    (1, N'Rafael Nunes',    N'VP of Engineering', 28000.00, '2017-05-15'),
    (1, N'Camila Rocha',    N'VP of Sales',       27000.00, '2017-08-01'),
    (2, N'Bruno Teixeira',  N'Engineering Manager', 18500.00, '2018-03-12'),
    (2, N'Larissa Moura',   N'Engineering Manager', 18500.00, '2019-01-07'),
    (3, N'Otavio Lima',     N'Sales Manager',       16000.00, '2018-11-20'),
    (4, N'Paula Andrade',   N'Senior Developer',    13000.00, '2020-06-01'),
    (4, N'Igor Cardoso',    N'Developer',            9500.00, '2021-09-13'),
    (5, N'Marina Souza',    N'Senior Developer',    13000.00, '2020-02-17'),
    (5, N'Tiago Barros',    N'Developer',            9200.00, '2022-04-04'),
    (6, N'Fernanda Dias',   N'Account Executive',    8800.00, '2021-01-25'),
    (6, N'Gustavo Pires',   N'Account Executive',    8600.00, '2022-07-11');
GO

SELECT 'Categories'  AS TableName, COUNT(*) AS Rows FROM dbo.Categories
UNION ALL SELECT 'Products',   COUNT(*) FROM dbo.Products
UNION ALL SELECT 'Customers',  COUNT(*) FROM dbo.Customers
UNION ALL SELECT 'Orders',     COUNT(*) FROM dbo.Orders
UNION ALL SELECT 'OrderItems', COUNT(*) FROM dbo.OrderItems
UNION ALL SELECT 'Employees',  COUNT(*) FROM dbo.Employees;
GO

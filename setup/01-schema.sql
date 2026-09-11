/*
    Sample schema used by every recipe in this repository.

    Domain: a small online store with customers, orders, products and categories.
    Run this script first, then 02-seed.sql.
*/

IF DB_ID('SqlRecipes') IS NULL
BEGIN
    CREATE DATABASE SqlRecipes;
END;
GO

USE SqlRecipes;
GO

DROP TABLE IF EXISTS dbo.OrderItems;
DROP TABLE IF EXISTS dbo.Orders;
DROP TABLE IF EXISTS dbo.Products;
DROP TABLE IF EXISTS dbo.Categories;
DROP TABLE IF EXISTS dbo.Customers;
DROP TABLE IF EXISTS dbo.Employees;
GO

CREATE TABLE dbo.Categories
(
    CategoryId   INT IDENTITY(1, 1) NOT NULL,
    Name         NVARCHAR(120)      NOT NULL,
    Description  NVARCHAR(500)      NULL,
    IsActive     BIT                NOT NULL CONSTRAINT DF_Categories_IsActive DEFAULT (1),
    CreatedAt    DATETIME2(3)       NOT NULL CONSTRAINT DF_Categories_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_Categories PRIMARY KEY CLUSTERED (CategoryId),
    CONSTRAINT UQ_Categories_Name UNIQUE (Name)
);
GO

CREATE TABLE dbo.Products
(
    ProductId    INT IDENTITY(1, 1) NOT NULL,
    CategoryId   INT                NOT NULL,
    Name         NVARCHAR(160)      NOT NULL,
    Sku          VARCHAR(32)        NOT NULL,
    UnitPrice    DECIMAL(18, 2)     NOT NULL,
    StockOnHand  INT                NOT NULL CONSTRAINT DF_Products_StockOnHand DEFAULT (0),
    IsActive     BIT                NOT NULL CONSTRAINT DF_Products_IsActive DEFAULT (1),
    CreatedAt    DATETIME2(3)       NOT NULL CONSTRAINT DF_Products_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_Products PRIMARY KEY CLUSTERED (ProductId),
    CONSTRAINT UQ_Products_Sku UNIQUE (Sku),
    CONSTRAINT FK_Products_Categories FOREIGN KEY (CategoryId) REFERENCES dbo.Categories (CategoryId),
    CONSTRAINT CK_Products_UnitPrice CHECK (UnitPrice > 0)
);
GO

CREATE TABLE dbo.Customers
(
    CustomerId   INT IDENTITY(1, 1) NOT NULL,
    FullName     NVARCHAR(200)      NOT NULL,
    Email        NVARCHAR(200)      NOT NULL,
    City         NVARCHAR(120)      NOT NULL,
    State        CHAR(2)            NOT NULL,
    CreatedAt    DATETIME2(3)       NOT NULL CONSTRAINT DF_Customers_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_Customers PRIMARY KEY CLUSTERED (CustomerId),
    CONSTRAINT UQ_Customers_Email UNIQUE (Email)
);
GO

CREATE TABLE dbo.Orders
(
    OrderId      INT IDENTITY(1, 1) NOT NULL,
    CustomerId   INT                NOT NULL,
    OrderNumber  VARCHAR(20)        NOT NULL,
    Status       VARCHAR(20)        NOT NULL,
    OrderDate    DATETIME2(3)       NOT NULL,
    ShippedDate  DATETIME2(3)       NULL,
    TotalAmount  DECIMAL(18, 2)     NOT NULL,
    CONSTRAINT PK_Orders PRIMARY KEY CLUSTERED (OrderId),
    CONSTRAINT UQ_Orders_OrderNumber UNIQUE (OrderNumber),
    CONSTRAINT FK_Orders_Customers FOREIGN KEY (CustomerId) REFERENCES dbo.Customers (CustomerId),
    CONSTRAINT CK_Orders_Status CHECK (Status IN ('Pending', 'Paid', 'Shipped', 'Delivered', 'Cancelled'))
);
GO

CREATE TABLE dbo.OrderItems
(
    OrderItemId  INT IDENTITY(1, 1) NOT NULL,
    OrderId      INT                NOT NULL,
    ProductId    INT                NOT NULL,
    Quantity     INT                NOT NULL,
    UnitPrice    DECIMAL(18, 2)     NOT NULL,
    Discount     DECIMAL(5, 4)      NOT NULL CONSTRAINT DF_OrderItems_Discount DEFAULT (0),
    CONSTRAINT PK_OrderItems PRIMARY KEY CLUSTERED (OrderItemId),
    CONSTRAINT FK_OrderItems_Orders FOREIGN KEY (OrderId) REFERENCES dbo.Orders (OrderId) ON DELETE CASCADE,
    CONSTRAINT FK_OrderItems_Products FOREIGN KEY (ProductId) REFERENCES dbo.Products (ProductId),
    CONSTRAINT CK_OrderItems_Quantity CHECK (Quantity > 0)
);
GO

/*
    Self referencing table used by the recursive CTE examples.
*/
CREATE TABLE dbo.Employees
(
    EmployeeId   INT IDENTITY(1, 1) NOT NULL,
    ManagerId    INT                NULL,
    FullName     NVARCHAR(200)      NOT NULL,
    JobTitle     NVARCHAR(120)      NOT NULL,
    Salary       DECIMAL(18, 2)     NOT NULL,
    HiredAt      DATE               NOT NULL,
    CONSTRAINT PK_Employees PRIMARY KEY CLUSTERED (EmployeeId),
    CONSTRAINT FK_Employees_Manager FOREIGN KEY (ManagerId) REFERENCES dbo.Employees (EmployeeId)
);
GO

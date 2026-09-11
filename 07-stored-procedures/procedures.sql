/*
    Stored procedures: parameters, output parameters, error handling and
    transactional writes.
*/

USE SqlRecipes;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ------------------------------------------------------------------------- */
/* A paged, filtered search with a total row count returned as an output.     */
/* ------------------------------------------------------------------------- */
DROP PROCEDURE IF EXISTS dbo.usp_SearchProducts;
GO

CREATE PROCEDURE dbo.usp_SearchProducts
    @Search     NVARCHAR(100) = NULL,
    @CategoryId INT           = NULL,
    @IsActive   BIT           = NULL,
    @Page       INT           = 1,
    @PageSize   INT           = 20,
    @TotalRows  INT           = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    IF @Page < 1 SET @Page = 1;
    IF @PageSize NOT BETWEEN 1 AND 100 SET @PageSize = 20;

    SELECT @TotalRows = COUNT(*)
    FROM dbo.Products AS p
    WHERE (@Search     IS NULL OR p.Name LIKE @Search + N'%')
      AND (@CategoryId IS NULL OR p.CategoryId = @CategoryId)
      AND (@IsActive   IS NULL OR p.IsActive = @IsActive);

    SELECT
        p.ProductId,
        p.Name,
        p.Sku,
        p.UnitPrice,
        p.StockOnHand,
        c.Name AS CategoryName
    FROM dbo.Products AS p
    INNER JOIN dbo.Categories AS c
        ON c.CategoryId = p.CategoryId
    WHERE (@Search     IS NULL OR p.Name LIKE @Search + N'%')
      AND (@CategoryId IS NULL OR p.CategoryId = @CategoryId)
      AND (@IsActive   IS NULL OR p.IsActive = @IsActive)
    ORDER BY p.Name, p.ProductId
    OFFSET (@Page - 1) * @PageSize ROWS
    FETCH NEXT @PageSize ROWS ONLY
    OPTION (RECOMPILE);   -- optional filters produce very different plans
END;
GO

DECLARE @Total INT;
EXEC dbo.usp_SearchProducts
    @Search     = N'Product 1',
    @Page       = 1,
    @PageSize   = 10,
    @TotalRows  = @Total OUTPUT;

SELECT @Total AS TotalMatchingRows;
GO

/* ------------------------------------------------------------------------- */
/* A transactional write with validation and structured error handling.       */
/* ------------------------------------------------------------------------- */
DROP PROCEDURE IF EXISTS dbo.usp_PlaceOrder;
GO

DROP SEQUENCE IF EXISTS dbo.OrderNumberSequence;
GO

CREATE SEQUENCE dbo.OrderNumberSequence AS INT START WITH 900000 INCREMENT BY 1;
GO

DROP TYPE IF EXISTS dbo.OrderItemList;
GO

CREATE TYPE dbo.OrderItemList AS TABLE
(
    ProductId INT NOT NULL,
    Quantity  INT NOT NULL
);
GO

CREATE PROCEDURE dbo.usp_PlaceOrder
    @CustomerId INT,
    @Items      dbo.OrderItemList READONLY,
    @OrderId    INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;   -- roll back the whole transaction on any error

    IF NOT EXISTS (SELECT 1 FROM dbo.Customers WHERE CustomerId = @CustomerId)
    BEGIN
        THROW 50001, 'Customer does not exist.', 1;
    END;

    IF NOT EXISTS (SELECT 1 FROM @Items)
    BEGIN
        THROW 50002, 'An order must contain at least one item.', 1;
    END;

    IF EXISTS
    (
        SELECT 1
        FROM @Items AS i
        LEFT JOIN dbo.Products AS p
            ON p.ProductId = i.ProductId
           AND p.IsActive = 1
        WHERE p.ProductId IS NULL
    )
    BEGIN
        THROW 50003, 'One or more products are unavailable.', 1;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @Total DECIMAL(18, 2) =
        (
            SELECT SUM(i.Quantity * p.UnitPrice)
            FROM @Items AS i
            INNER JOIN dbo.Products AS p
                ON p.ProductId = i.ProductId
        );

        INSERT INTO dbo.Orders (CustomerId, OrderNumber, Status, OrderDate, TotalAmount)
        VALUES
        (
            @CustomerId,
            CONCAT('ORD-', RIGHT(CONCAT('000000', NEXT VALUE FOR dbo.OrderNumberSequence), 6)),
            'Pending',
            SYSUTCDATETIME(),
            @Total
        );

        SET @OrderId = SCOPE_IDENTITY();

        INSERT INTO dbo.OrderItems (OrderId, ProductId, Quantity, UnitPrice, Discount)
        SELECT @OrderId, i.ProductId, i.Quantity, p.UnitPrice, 0
        FROM @Items AS i
        INNER JOIN dbo.Products AS p
            ON p.ProductId = i.ProductId;

        UPDATE p
        SET p.StockOnHand = p.StockOnHand - i.Quantity
        FROM dbo.Products AS p
        INNER JOIN @Items AS i
            ON i.ProductId = p.ProductId;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        THROW;   -- re-raise preserving the original error number and message
    END CATCH;
END;
GO

DECLARE @Items dbo.OrderItemList;
INSERT INTO @Items (ProductId, Quantity) VALUES (1, 2), (5, 1), (12, 3);

DECLARE @NewOrderId INT;
EXEC dbo.usp_PlaceOrder @CustomerId = 1, @Items = @Items, @OrderId = @NewOrderId OUTPUT;

SELECT @NewOrderId AS CreatedOrderId;

SELECT o.OrderNumber, o.TotalAmount, COUNT(oi.OrderItemId) AS Items
FROM dbo.Orders AS o
INNER JOIN dbo.OrderItems AS oi ON oi.OrderId = o.OrderId
WHERE o.OrderId = @NewOrderId
GROUP BY o.OrderNumber, o.TotalAmount;
GO

/* The validation path rolls back and surfaces a usable error. */
BEGIN TRY
    DECLARE @Empty dbo.OrderItemList;
    EXEC dbo.usp_PlaceOrder @CustomerId = 1, @Items = @Empty;
END TRY
BEGIN CATCH
    SELECT
        ERROR_NUMBER()  AS ErrorNumber,
        ERROR_MESSAGE() AS ErrorMessage;
END CATCH;
GO

/* ------------------------------------------------------------------------- */
/* A concurrency safe upsert: try the update first, insert only if it missed. */
/* ------------------------------------------------------------------------- */
DROP PROCEDURE IF EXISTS dbo.usp_UpsertCategory;
GO

CREATE PROCEDURE dbo.usp_UpsertCategory
    @Name        NVARCHAR(120),
    @Description NVARCHAR(500) = NULL,
    @CategoryId  INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    /*
        UPDLOCK plus HOLDLOCK takes a range lock on the key, so a concurrent
        session cannot insert the same Name between this update and the insert
        below. Without it, two sessions racing on a new key both see zero rows
        updated and both insert, violating the unique constraint.

        MERGE is the more compact form but has a history of concurrency and
        correctness issues, so this pattern is the safer default.
    */
    UPDATE dbo.Categories WITH (UPDLOCK, HOLDLOCK)
    SET Description = @Description,
        @CategoryId = CategoryId
    WHERE Name = @Name;

    IF @@ROWCOUNT = 0
    BEGIN
        INSERT INTO dbo.Categories (Name, Description)
        VALUES (@Name, @Description);

        SET @CategoryId = SCOPE_IDENTITY();
    END;

    COMMIT TRANSACTION;
END;
GO

DECLARE @Id INT;
EXEC dbo.usp_UpsertCategory @Name = N'Electronics', @Description = N'Updated description', @CategoryId = @Id OUTPUT;
SELECT @Id AS ExistingCategoryUpdated;

EXEC dbo.usp_UpsertCategory @Name = N'Music', @Description = N'Instruments and audio', @CategoryId = @Id OUTPUT;
SELECT @Id AS NewCategoryInserted;

DELETE FROM dbo.Categories WHERE Name = N'Music';
GO

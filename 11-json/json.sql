/*
    JSON in SQL Server: producing, consuming and indexing.
*/

USE SqlRecipes;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ------------------------------------------------------------------------- */
/* Producing JSON: FOR JSON                                                   */
/* ------------------------------------------------------------------------- */
/* FOR JSON PATH: dotted aliases become nested objects. */
SELECT TOP (3)
    o.OrderId          AS 'id',
    o.OrderNumber      AS 'number',
    o.Status           AS 'status',
    o.TotalAmount      AS 'total',
    c.FullName         AS 'customer.name',
    c.Email            AS 'customer.email',
    c.State            AS 'customer.state'
FROM dbo.Orders AS o
INNER JOIN dbo.Customers AS c
    ON c.CustomerId = o.CustomerId
FOR JSON PATH;
GO

/* WITHOUT_ARRAY_WRAPPER returns a single object instead of an array. */
SELECT
    o.OrderNumber AS 'number',
    o.TotalAmount AS 'total'
FROM dbo.Orders AS o
WHERE o.OrderId = 1
FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
GO

/*
    Nested collections: a correlated subquery with FOR JSON PATH becomes an
    array property on the parent object.
*/
SELECT TOP (2)
    o.OrderNumber AS 'number',
    o.Status      AS 'status',
    (
        SELECT
            p.Name       AS 'product',
            oi.Quantity  AS 'quantity',
            oi.UnitPrice AS 'unitPrice'
        FROM dbo.OrderItems AS oi
        INNER JOIN dbo.Products AS p
            ON p.ProductId = oi.ProductId
        WHERE oi.OrderId = o.OrderId
        FOR JSON PATH
    ) AS 'items'
FROM dbo.Orders AS o
FOR JSON PATH;
GO

/* INCLUDE_NULL_VALUES keeps null properties, which are omitted by default. */
SELECT TOP (2)
    o.OrderNumber AS 'number',
    o.ShippedDate AS 'shippedAt'
FROM dbo.Orders AS o
WHERE o.ShippedDate IS NULL
FOR JSON PATH, INCLUDE_NULL_VALUES;
GO

/* ------------------------------------------------------------------------- */
/* Consuming JSON: OPENJSON, JSON_VALUE, JSON_QUERY                           */
/* ------------------------------------------------------------------------- */
DECLARE @Payload NVARCHAR(MAX) = N'
{
    "orderNumber": "ORD-999001",
    "customer": { "id": 42, "name": "Ana Souza", "vip": true },
    "items": [
        { "sku": "SKU-0001", "quantity": 2, "unitPrice": 27.25 },
        { "sku": "SKU-0005", "quantity": 1, "unitPrice": 56.65 },
        { "sku": "SKU-0012", "quantity": 3, "unitPrice": 107.80 }
    ]
}';

/* ISJSON validates before parsing. */
SELECT ISJSON(@Payload) AS IsValidJson;

/* JSON_VALUE extracts a scalar. JSON_QUERY extracts an object or array. */
SELECT
    JSON_VALUE(@Payload, '$.orderNumber')        AS OrderNumber,
    JSON_VALUE(@Payload, '$.customer.name')      AS CustomerName,
    JSON_VALUE(@Payload, '$.customer.id')        AS CustomerId,
    JSON_QUERY(@Payload, '$.customer')           AS CustomerObject,
    JSON_QUERY(@Payload, '$.items')              AS ItemsArray,
    JSON_VALUE(@Payload, '$.items[0].sku')       AS FirstItemSku;

/* OPENJSON with a schema turns an array into a relational rowset. */
SELECT *
FROM OPENJSON(@Payload, '$.items')
WITH
(
    Sku       VARCHAR(32)    '$.sku',
    Quantity  INT            '$.quantity',
    UnitPrice DECIMAL(18, 2) '$.unitPrice'
);

/* Joining parsed JSON against real tables is the usual import pattern. */
SELECT
    items.Sku,
    p.ProductId,
    p.Name,
    items.Quantity,
    items.UnitPrice,
    items.Quantity * items.UnitPrice AS LineTotal
FROM OPENJSON(@Payload, '$.items')
WITH
(
    Sku       VARCHAR(32)    '$.sku',
    Quantity  INT            '$.quantity',
    UnitPrice DECIMAL(18, 2) '$.unitPrice'
) AS items
INNER JOIN dbo.Products AS p
    ON p.Sku = items.Sku;

/* Without a schema, OPENJSON returns key, value and type. */
SELECT [key], [value], [type]
FROM OPENJSON(@Payload, '$.customer');
GO

/* ------------------------------------------------------------------------- */
/* Storing JSON in a column                                                   */
/* ------------------------------------------------------------------------- */
DROP TABLE IF EXISTS dbo.WebhookEvents;
GO

CREATE TABLE dbo.WebhookEvents
(
    EventId    INT IDENTITY(1, 1) NOT NULL,
    Source     VARCHAR(50)        NOT NULL,
    Payload    NVARCHAR(MAX)      NOT NULL,
    ReceivedAt DATETIME2(3)       NOT NULL CONSTRAINT DF_WebhookEvents_ReceivedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_WebhookEvents PRIMARY KEY CLUSTERED (EventId),
    /* A CHECK constraint keeps invalid documents out of the column. */
    CONSTRAINT CK_WebhookEvents_Payload CHECK (ISJSON(Payload) = 1)
);
GO

INSERT INTO dbo.WebhookEvents (Source, Payload)
VALUES
    ('stripe', N'{"type":"payment.succeeded","data":{"amount":4990,"currency":"brl","paid":true}}'),
    ('stripe', N'{"type":"payment.failed","data":{"amount":12900,"currency":"brl","paid":false}}'),
    ('github', N'{"type":"push","data":{"ref":"refs/heads/main","commits":3}}');
GO

/* Rejected by the CHECK constraint. */
BEGIN TRY
    INSERT INTO dbo.WebhookEvents (Source, Payload) VALUES ('broken', N'not json at all');
END TRY
BEGIN CATCH
    PRINT 'Rejected as expected: ' + ERROR_MESSAGE();
END CATCH;
GO

/*
    Indexing a JSON property. There is no JSON index type: expose the property
    as a computed column and index that.
*/
ALTER TABLE dbo.WebhookEvents
ADD EventType AS CAST(JSON_VALUE(Payload, '$.type') AS VARCHAR(60));
GO

CREATE NONCLUSTERED INDEX IX_WebhookEvents_EventType
    ON dbo.WebhookEvents (EventType)
    INCLUDE (Source, ReceivedAt);
GO

/* This now seeks instead of parsing every document. */
SELECT EventId, Source, EventType, ReceivedAt
FROM dbo.WebhookEvents
WHERE EventType = 'payment.succeeded';
GO

/* Aggregating over stored documents. */
SELECT
    e.Source,
    e.EventType,
    COUNT(*)                                                  AS Events,
    SUM(CAST(JSON_VALUE(e.Payload, '$.data.amount') AS INT))  AS TotalAmountCents
FROM dbo.WebhookEvents AS e
GROUP BY e.Source, e.EventType
ORDER BY e.Source, e.EventType;
GO

/* Modifying a document in place. */
UPDATE dbo.WebhookEvents
SET Payload = JSON_MODIFY(Payload, '$.data.processed', CAST(1 AS BIT))
WHERE EventType = 'payment.succeeded';

SELECT Payload FROM dbo.WebhookEvents WHERE EventType = 'payment.succeeded';
GO

/*
    When to store JSON and when not to

    Good fit
        - Raw webhook and integration payloads kept for replay or audit
        - Sparse, caller defined attributes that vary per row
        - Documents your application treats as opaque

    Bad fit
        - Anything you filter, join or aggregate on regularly
        - Data with a stable shape, which belongs in columns
        - Anything needing referential integrity, which JSON cannot express
*/

DROP TABLE IF EXISTS dbo.WebhookEvents;
GO

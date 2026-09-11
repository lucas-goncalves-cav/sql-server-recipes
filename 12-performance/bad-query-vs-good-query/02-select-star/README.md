# SELECT star

## Measured

Query filtering `Status = 'Delivered'` with a covering index on `(Status) INCLUDE (OrderNumber, TotalAmount)`:

| Version | Logical reads | Plan |
| --- | --- | --- |
| `bad.sql` | 159 | Clustered index scan |
| `good.sql` | 25 | Index seek, covered |

## Why

The index contains `Status`, `OrderNumber` and `TotalAmount`. `SELECT *` also asks for `CustomerId`, `OrderDate` and
`ShippedDate`, which are not there. Rather than seek the index and then look up thousands of rows in the table, the
optimizer gives up on the index and scans the table directly.

Naming the three columns that are actually needed lets the index cover the query, and the table is never touched.

## The other costs

- **Network**: every unused column is serialized and sent
- **Memory grant**: wider rows mean a larger grant, which can spill sorts to tempdb
- **Fragility**: adding a column to the table silently changes the result shape
- **Views**: a `SELECT *` view does not pick up new columns until refreshed with `sp_refreshview`

## When it is fine

- Ad hoc exploration in a query window
- `EXISTS (SELECT * FROM ...)`, where the column list is never evaluated
- `COUNT(*)`, which counts rows rather than reading columns

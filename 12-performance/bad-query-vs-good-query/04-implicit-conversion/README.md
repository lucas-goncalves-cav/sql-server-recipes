# Implicit Conversion

## Measured

Looking up a single product by `Sku`, a `VARCHAR(32)` column, with a covering index:

| Version | Parameter type | Logical reads | Plan |
| --- | --- | --- | --- |
| `bad.sql` | `NVARCHAR(32)` | 4 | Index **scan** |
| `good.sql` | `VARCHAR(32)` | 2 | Index **seek** |

The absolute numbers are small because `Products` holds only 200 rows. What matters is that the plan changed from a
scan to a seek. On a table with millions of rows, that same change is the difference between milliseconds and minutes.

## Why

SQL Server has a fixed data type precedence order. `NVARCHAR` ranks higher than `VARCHAR`, so when the two are
compared, the `VARCHAR` side is converted, not the parameter.

That side is the **column**. Every row must be converted before it can be compared, which is the sargability problem
from case 01 arriving through a side door.

The plan shows it as a `CONVERT_IMPLICIT` warning on the operator.

## Why it shows up so often

Most ORMs and drivers send strings as Unicode by default. A .NET application querying a `VARCHAR` column with a plain
string parameter produces this every single time:

```csharp
// Sends NVARCHAR, forces a conversion on the column
command.Parameters.AddWithValue("@Sku", sku);

// Sends VARCHAR, index seeks
command.Parameters.Add("@Sku", SqlDbType.VarChar, 32).Value = sku;
```

Dapper has the same distinction through `DbString`:

```csharp
new DbString { Value = sku, IsAnsi = true, Length = 32 }
```

## Direction matters

A conversion on the **parameter** side is harmless: the engine converts the single value once and then seeks normally.
Only a conversion applied to the column breaks the index.

## Finding them

The plan XML records every one:

```sql
SELECT TOP (20)
    qp.query_plan,
    qs.execution_count,
    qs.total_logical_reads
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) AS qp
WHERE CAST(qp.query_plan AS NVARCHAR(MAX)) LIKE '%CONVERT_IMPLICIT%'
ORDER BY qs.total_logical_reads DESC;
```

## Other pairs that do the same thing

| Column type | Compared to | Result |
| --- | --- | --- |
| `VARCHAR` | `NVARCHAR` | Column converted, scan |
| `INT` | `VARCHAR` | Column converted, scan |
| `DATE` | `VARCHAR` | Depends on the literal, often a scan |
| `NVARCHAR` | `VARCHAR` | Parameter converted, seek, harmless |

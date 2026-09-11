# Stored Procedures

## Files

| File | Content |
| --- | --- |
| `procedures.sql` | Paged search with output parameter, transactional write with a table valued parameter, concurrency safe upsert |

## What every procedure should start with

```sql
SET NOCOUNT ON;     -- stop sending "n rows affected" messages to the client
SET XACT_ABORT ON;  -- roll the transaction back on any error, not just some
```

`SET NOCOUNT ON` removes a network round trip per statement. `SET XACT_ABORT ON` matters more: without it, several
runtime errors abort only the statement and leave the transaction open and partially applied.

## Error handling

`THROW` re-raises the current error with its original number, message and line. `RAISERROR` cannot do that and always
reports its own line. Inside `CATCH`, check `XACT_STATE()` before rolling back:

| `XACT_STATE()` | Meaning |
| --- | --- |
| `1` | Active transaction, commit or rollback both possible |
| `0` | No transaction |
| `-1` | Doomed transaction, only rollback is allowed |

## Table valued parameters

A TVP sends a whole set in one call instead of looping row by row from the application. The type is declared once and
the parameter must be `READONLY`:

```sql
CREATE TYPE dbo.OrderItemList AS TABLE (ProductId INT NOT NULL, Quantity INT NOT NULL);

CREATE PROCEDURE dbo.usp_PlaceOrder
    @Items dbo.OrderItemList READONLY
AS ...
```

## Parameter sniffing

SQL Server builds the plan using the parameter values of the first execution and reuses it. With optional filters, the
plan chosen for `@CategoryId = NULL` can be terrible for `@CategoryId = 3`.

| Fix | Cost |
| --- | --- |
| `OPTION (RECOMPILE)` | New plan every execution, compile cost per call |
| `OPTIMIZE FOR UNKNOWN` | One average plan, good for nobody in particular |
| Local variable copies | Same effect as `OPTIMIZE FOR UNKNOWN` |
| Dynamic SQL per filter combination | Best plans, more code, watch for injection |

For a search procedure with several optional filters, `OPTION (RECOMPILE)` is usually the right trade.

## Naming

Never prefix a procedure with `sp_`. SQL Server looks for that prefix in `master` first, which costs an extra lookup and
can silently resolve to a system procedure. `usp_` or a domain prefix is fine.

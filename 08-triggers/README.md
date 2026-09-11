# Triggers

## Files

| File | Content |
| --- | --- |
| `triggers.sql` | `AFTER` trigger for auditing, `INSTEAD OF` trigger on a view, cross table rule enforcement |

## The rule that breaks most triggers

**A trigger fires once per statement, not once per row.** `inserted` and `deleted` are tables, and a single `UPDATE`
can put thousands of rows in them.

```sql
-- Wrong: silently handles only one of the affected rows
DECLARE @ProductId INT = (SELECT ProductId FROM inserted);

-- Right: set based, handles any number of rows
INSERT INTO dbo.Audit (ProductId, OldPrice, NewPrice)
SELECT i.ProductId, d.UnitPrice, i.UnitPrice
FROM inserted AS i
INNER JOIN deleted AS d ON d.ProductId = i.ProductId;
```

In `triggers.sql`, one `UPDATE` affecting 40 products produces 40 audit rows.

## inserted and deleted

| Operation | `inserted` | `deleted` |
| --- | --- | --- |
| `INSERT` | New rows | Empty |
| `UPDATE` | New values | Old values |
| `DELETE` | Empty | Removed rows |

A `FULL JOIN` between the two handles all three cases in one statement.

## AFTER vs INSTEAD OF

| | `AFTER` | `INSTEAD OF` |
| --- | --- | --- |
| Runs | After the operation, inside the same transaction | In place of the operation |
| Target | Tables | Tables and views |
| Typical use | Auditing, cross table rules | Making a multi table view updatable |

An `INSTEAD OF` trigger replaces the statement entirely. If it does not write anything, nothing is written.

## UPDATE() is about the statement, not the value

`UPDATE(UnitPrice)` returns true when the column appeared in the `SET` list, even if the value did not change. To detect
a real change, compare `inserted` with `deleted`.

## Transactions and errors

A trigger runs inside the transaction of the statement that fired it, with `XACT_ABORT` implicitly on. A `THROW` inside
a trigger rolls back everything, including work done before the statement. That is what makes triggers usable for
enforcing invariants, and also what makes a slow trigger extend every transaction that touches the table.

## When not to use a trigger

Triggers are invisible at the call site. Someone reading the `INSERT` has no indication that three other tables are
being written. Prefer the explicit option when one exists:

| Need | Prefer |
| --- | --- |
| Value must be in a set or range | `CHECK` constraint |
| Reference must exist | `FOREIGN KEY` |
| Default value | `DEFAULT` constraint |
| Denormalized aggregate | Indexed view |
| Full row history | Temporal tables (`SYSTEM_VERSIONING`) |

Reach for a trigger when the rule spans tables and none of the above can express it.

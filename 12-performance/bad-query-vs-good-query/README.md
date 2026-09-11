# Bad Query vs Good Query

Five pairs of queries that return the same rows with very different cost. Each folder holds `bad.sql`, `good.sql` and a
`README.md` explaining why.

Every number below was measured against the seeded database in `setup/` on SQL Server 2022, using
`SET STATISTICS IO ON` for reads and wall clock timing for the cursor comparison. Run them yourself, the numbers will
shift with hardware but the ratios hold.

## Results

| Case | Bad | Good | Difference |
| --- | --- | --- | --- |
| [01 Sargability](01-sargability/) | 101 reads | 4 reads | 25x fewer reads |
| [02 SELECT star](02-select-star/) | 159 reads | 25 reads | 6x fewer reads |
| [03 Row by row](03-row-by-row/) | 76,408 ms | 47 ms | 1,600x faster |
| [04 Implicit conversion](04-implicit-conversion/) | 4 reads, scan | 2 reads, seek | Scan becomes a seek |
| [05 Correlated subquery](05-correlated-subquery/) | 477 reads, 3 scans | 159 reads, 1 scan | 3x fewer reads |

## How to run a comparison

```sql
-- In SSMS or Azure Data Studio, enable the actual execution plan with Ctrl+M
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
```

Then run `bad.sql`, note the reads, run `good.sql`, compare. The execution plan shows the real story: look for the
operator that changed from **Scan** to **Seek**, and for a missing **Key Lookup**.

## The one number that matters

**Logical reads**, not elapsed time. Elapsed time depends on what is already in the buffer pool, what else the server is
doing, and how busy the disk is. Logical reads count the pages the query actually had to touch, and that number is
stable between runs. A query that reads fewer pages will be faster under load even when it looks identical on an idle
development machine.

## The pattern behind all five

Four of the five are the same mistake in different clothing: **making the engine evaluate something per row that could
have been decided once.** A function on a column, an implicit conversion, a correlated subquery and a cursor all force
row at a time work where a set based operation was available.

The fifth, `SELECT *`, is the mistake of asking for more than you need and losing the ability to cover the query with
an index.

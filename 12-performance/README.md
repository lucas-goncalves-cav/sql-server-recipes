# Performance

## Files

| Path | Content |
| --- | --- |
| `diagnostics.sql` | Live requests, most expensive queries, wait statistics, stale statistics, object sizes, Query Store |
| `bad-query-vs-good-query/` | Five measured comparisons of the same result at very different cost |

## Where to start when the database is slow

1. **What is running right now.** `sys.dm_exec_requests` shows active queries, their waits and who is blocking whom.
2. **What has been expensive.** `sys.dm_exec_query_stats` ordered by `total_logical_reads`, then by `total_worker_time`.
3. **What the server waits on.** `sys.dm_os_wait_stats` says whether the bottleneck is IO, locking, CPU or memory.
4. **Whether the estimates are right.** A plan built on stale statistics picks the wrong join and the wrong grant.

Only then look at individual queries. Optimizing the query somebody happened to complain about, while a different one
runs ten thousand times a minute, is how afternoons disappear.

## Total, not average

A query costing 50 reads that runs 100,000 times an hour costs 5,000,000 reads. A query costing 500,000 reads that runs
nightly costs 500,000. The first one is the problem, and sorting by average cost hides it completely.

## Reading wait statistics

| Wait type | Usually means |
| --- | --- |
| `PAGEIOLATCH_*` | Reading from disk, frequently a missing index |
| `LCK_M_*` | Blocking, look at transaction length and isolation level |
| `WRITELOG` | Log write latency, check storage and commit frequency |
| `RESOURCE_SEMAPHORE` | Memory grant pressure, often caused by bad estimates |
| `SOS_SCHEDULER_YIELD` | CPU pressure |
| `CXPACKET` / `CXCONSUMER` | Parallelism, usually a symptom of another problem |

`sys.dm_os_wait_stats` accumulates since the last restart. Either reset it with
`DBCC SQLPERF('sys.dm_os_wait_stats', CLEAR)` before a test, or take two snapshots and diff them.

## Logical reads over elapsed time

Elapsed time varies with what is in the buffer pool, what else the server is doing, and how busy the storage is. Run
the same query twice and the second is faster for reasons that have nothing to do with the query.

Logical reads count the pages the query had to touch. That number is stable, comparable between two versions, and
predicts behaviour under load. When comparing two queries, compare reads.

## The optimizer is usually right

Before adding a hint, assume the optimizer had a reason. It picked a scan over a seek because the seek would have
needed too many lookups. It chose a hash join because the input was not sorted. Hints like `FORCESEEK`, `INDEX =` and
`OPTION (FORCE ORDER)` freeze a decision that was correct on the day it was written and will be wrong once the data
distribution changes.

Fix the cause instead: the missing index, the non sargable predicate, the stale statistics, the implicit conversion.

/*
    Diagnostics: finding the queries that are actually hurting.

    Start here when someone says "the database is slow". Work from evidence,
    not from the query somebody happens to remember.
*/

USE SqlRecipes;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ------------------------------------------------------------------------- */
/* 1. What is running right now                                               */
/* ------------------------------------------------------------------------- */
SELECT
    r.session_id,
    r.status,
    r.command,
    r.wait_type,
    r.wait_time                                   AS WaitMs,
    r.blocking_session_id,
    r.cpu_time                                    AS CpuMs,
    r.total_elapsed_time                          AS ElapsedMs,
    r.logical_reads,
    DB_NAME(r.database_id)                        AS DatabaseName,
    SUBSTRING(t.text,
              (r.statement_start_offset / 2) + 1,
              CASE r.statement_end_offset
                  WHEN -1 THEN DATALENGTH(t.text)
                  ELSE (r.statement_end_offset - r.statement_start_offset) / 2
              END + 1)                            AS RunningStatement
FROM sys.dm_exec_requests AS r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
WHERE r.session_id <> @@SPID
  AND r.session_id > 50
ORDER BY r.total_elapsed_time DESC;
GO

/* ------------------------------------------------------------------------- */
/* 2. Most expensive queries by total logical reads                           */
/* ------------------------------------------------------------------------- */
/*
    Total, not average. A query costing 50 reads that runs 100,000 times a
    minute hurts far more than one costing 500,000 reads that runs nightly.
*/
SELECT TOP (20)
    qs.execution_count                                          AS Executions,
    qs.total_logical_reads                                      AS TotalReads,
    qs.total_logical_reads / qs.execution_count                 AS AvgReads,
    qs.total_worker_time / 1000                                 AS TotalCpuMs,
    qs.total_worker_time / qs.execution_count / 1000            AS AvgCpuMs,
    qs.total_elapsed_time / qs.execution_count / 1000           AS AvgElapsedMs,
    qs.last_execution_time,
    SUBSTRING(t.text,
              (qs.statement_start_offset / 2) + 1,
              CASE qs.statement_end_offset
                  WHEN -1 THEN DATALENGTH(t.text)
                  ELSE (qs.statement_end_offset - qs.statement_start_offset) / 2
              END + 1)                                          AS QueryText
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS t
ORDER BY qs.total_logical_reads DESC;
GO

/* Same list ordered by CPU, which surfaces different offenders. */
SELECT TOP (20)
    qs.execution_count,
    qs.total_worker_time / 1000                      AS TotalCpuMs,
    qs.total_worker_time / qs.execution_count / 1000 AS AvgCpuMs,
    SUBSTRING(t.text,
              (qs.statement_start_offset / 2) + 1,
              CASE qs.statement_end_offset
                  WHEN -1 THEN DATALENGTH(t.text)
                  ELSE (qs.statement_end_offset - qs.statement_start_offset) / 2
              END + 1) AS QueryText
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS t
ORDER BY qs.total_worker_time DESC;
GO

/* ------------------------------------------------------------------------- */
/* 3. Wait statistics: what the server spends its time waiting for            */
/* ------------------------------------------------------------------------- */
/*
    Benign waits are filtered out. The top real wait usually points at the
    category of problem:

        PAGEIOLATCH_*   reading from disk, often missing indexes
        LCK_M_*         blocking, look at isolation and transaction length
        CXPACKET        parallelism, often a symptom rather than a cause
        WRITELOG        log write latency, check storage
        RESOURCE_SEMAPHORE  memory grant pressure, often from bad estimates
        SOS_SCHEDULER_YIELD CPU pressure
*/
WITH Waits AS
(
    SELECT
        wait_type,
        wait_time_ms,
        waiting_tasks_count,
        signal_wait_time_ms,
        100.0 * wait_time_ms / SUM(wait_time_ms) OVER () AS Percentage
    FROM sys.dm_os_wait_stats
    WHERE wait_time_ms > 0
      AND wait_type NOT IN
      (
          'CLR_SEMAPHORE', 'LAZYWRITER_SLEEP', 'RESOURCE_QUEUE', 'SLEEP_TASK',
          'SLEEP_SYSTEMTASK', 'SQLTRACE_BUFFER_FLUSH', 'WAITFOR', 'BROKER_TASK_STOP',
          'CHECKPOINT_QUEUE', 'REQUEST_FOR_DEADLOCK_SEARCH', 'XE_TIMER_EVENT',
          'BROKER_TO_FLUSH', 'DIRTY_PAGE_POLL', 'HADR_FILESTREAM_IOMGR_IOCOMPLETION',
          'SP_SERVER_DIAGNOSTICS_SLEEP', 'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP',
          'QDS_ASYNC_QUEUE', 'QDS_SHUTDOWN_QUEUE', 'XE_DISPATCHER_WAIT',
          'PREEMPTIVE_XE_GETTARGETSTATE', 'BROKER_EVENTHANDLER', 'SLEEP_DBSTARTUP',
          'DISPATCHER_QUEUE_SEMAPHORE'
      )
)
SELECT TOP (15)
    wait_type,
    waiting_tasks_count                          AS WaitCount,
    wait_time_ms                                 AS TotalWaitMs,
    wait_time_ms / NULLIF(waiting_tasks_count, 0) AS AvgWaitMs,
    signal_wait_time_ms                          AS CpuWaitMs,
    CAST(Percentage AS DECIMAL(5, 2))            AS PercentOfTotal
FROM Waits
ORDER BY wait_time_ms DESC;
GO

/* ------------------------------------------------------------------------- */
/* 4. Estimated vs actual rows                                                */
/* ------------------------------------------------------------------------- */
/*
    A plan built on a bad estimate picks the wrong join type, the wrong memory
    grant and sometimes the wrong index. Stale statistics are the usual cause.
*/
SELECT
    OBJECT_NAME(s.object_id)                        AS TableName,
    s.name                                          AS StatisticName,
    sp.last_updated,
    sp.rows                                         AS RowsAtLastUpdate,
    sp.rows_sampled,
    sp.modification_counter                         AS ModificationsSince,
    CASE
        WHEN sp.rows = 0 THEN NULL
        ELSE CAST(100.0 * sp.modification_counter / sp.rows AS DECIMAL(8, 2))
    END                                             AS PercentChanged
FROM sys.stats AS s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) AS sp
WHERE OBJECTPROPERTY(s.object_id, 'IsUserTable') = 1
  AND sp.rows > 0
ORDER BY PercentChanged DESC;
GO

/* Refresh statistics for a table when the modification counter is high. */
-- UPDATE STATISTICS dbo.Orders WITH FULLSCAN;

/* ------------------------------------------------------------------------- */
/* 5. Table and index sizes                                                   */
/* ------------------------------------------------------------------------- */
SELECT
    OBJECT_NAME(i.object_id)                                    AS TableName,
    ISNULL(i.name, 'HEAP')                                      AS IndexName,
    i.type_desc,
    SUM(p.rows)                                                 AS [Rows],
    CAST(SUM(a.total_pages) * 8.0 / 1024 AS DECIMAL(10, 2))     AS TotalMB,
    CAST(SUM(a.used_pages) * 8.0 / 1024 AS DECIMAL(10, 2))      AS UsedMB
FROM sys.indexes AS i
INNER JOIN sys.partitions AS p
    ON p.object_id = i.object_id AND p.index_id = i.index_id
INNER JOIN sys.allocation_units AS a
    ON a.container_id = p.partition_id
WHERE OBJECTPROPERTY(i.object_id, 'IsUserTable') = 1
GROUP BY i.object_id, i.name, i.type_desc, i.index_id
ORDER BY TotalMB DESC;
GO

/* ------------------------------------------------------------------------- */
/* 6. Query Store                                                             */
/* ------------------------------------------------------------------------- */
/*
    Query Store survives restarts and keeps plan history, which the DMVs above
    do not. Enable it on any database you care about:

        ALTER DATABASE SqlRecipes SET QUERY_STORE = ON
            (OPERATION_MODE = READ_WRITE, QUERY_CAPTURE_MODE = AUTO);

    Its main value is catching a query whose plan changed for the worse, which
    is invisible from sys.dm_exec_query_stats after a recompile.
*/
SELECT
    d.name,
    d.is_query_store_on,
    qs.desired_state_desc,
    qs.actual_state_desc,
    qs.query_capture_mode_desc
FROM sys.databases AS d
LEFT JOIN sys.database_query_store_options AS qs
    ON d.database_id = DB_ID()
WHERE d.name = DB_NAME();
GO

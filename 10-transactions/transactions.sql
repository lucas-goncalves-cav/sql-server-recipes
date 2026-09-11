/*
    Transactions: isolation levels, error handling and deadlocks.
*/

USE SqlRecipes;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ------------------------------------------------------------------------- */
/* The shape every write transaction should have                              */
/* ------------------------------------------------------------------------- */
/*
    XACT_ABORT ON matters more than it looks. Without it, several runtime
    errors abort only the failing statement and leave the transaction open,
    so a later COMMIT persists a partial change.
*/
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    UPDATE dbo.Products
    SET StockOnHand = StockOnHand - 1
    WHERE ProductId = 1;

    INSERT INTO dbo.ProductPriceAudit (ProductId, OldPrice, NewPrice, Action)
    SELECT ProductId, UnitPrice, UnitPrice, 'RESERVE'
    FROM dbo.Products
    WHERE ProductId = 1;

    COMMIT TRANSACTION;
    PRINT 'Committed.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    PRINT 'Rolled back: ' + ERROR_MESSAGE();
    THROW;
END CATCH;
GO

/*
    XACT_STATE()
         1  Active transaction, commit or rollback both allowed
         0  No transaction
        -1  Doomed transaction, only rollback is allowed

    @@TRANCOUNT only counts nesting depth and says nothing about whether the
    transaction can still be committed. Check XACT_STATE() in CATCH.
*/

/* ------------------------------------------------------------------------- */
/* Nested transactions are a naming convention, not real nesting              */
/* ------------------------------------------------------------------------- */
/*
    An inner BEGIN TRANSACTION only increments @@TRANCOUNT. Only the outermost
    COMMIT actually commits, but ANY rollback undoes EVERYTHING.
*/
BEGIN TRANSACTION;
    SELECT @@TRANCOUNT AS AfterOuterBegin;

    BEGIN TRANSACTION;
        SELECT @@TRANCOUNT AS AfterInnerBegin;
    COMMIT TRANSACTION;          -- decrements only

    SELECT @@TRANCOUNT AS AfterInnerCommit;
COMMIT TRANSACTION;              -- this one really commits

SELECT @@TRANCOUNT AS AfterOuterCommit;
GO

/* Savepoints give real partial rollback. */
BEGIN TRANSACTION;

    INSERT INTO dbo.Categories (Name, Description) VALUES (N'Savepoint Demo A', N'Keep');

    SAVE TRANSACTION BeforeSecondInsert;

    INSERT INTO dbo.Categories (Name, Description) VALUES (N'Savepoint Demo B', N'Discard');

    ROLLBACK TRANSACTION BeforeSecondInsert;   -- undoes only the second insert

COMMIT TRANSACTION;

SELECT Name FROM dbo.Categories WHERE Name LIKE N'Savepoint Demo%';

DELETE FROM dbo.Categories WHERE Name LIKE N'Savepoint Demo%';
GO

/* ------------------------------------------------------------------------- */
/* Isolation levels                                                           */
/* ------------------------------------------------------------------------- */
/*
    Level                Dirty read  Non repeatable read  Phantom read
    READ UNCOMMITTED     Possible    Possible             Possible
    READ COMMITTED       No          Possible             Possible     <- default
    REPEATABLE READ      No          No                   Possible
    SERIALIZABLE         No          No                   No
    SNAPSHOT             No          No                   No

    READ UNCOMMITTED, and its alias WITH (NOLOCK), does not mean "no locking
    problems". It means reading data that may never be committed, and it can
    also skip or duplicate rows when a page split happens mid scan. It is not
    a performance setting.
*/

/* Current level. */
SELECT
    transaction_isolation_level,
    CHOOSE(transaction_isolation_level + 1,
           'Unspecified', 'ReadUncommitted', 'ReadCommitted',
           'Repeatable', 'Serializable', 'Snapshot') AS LevelName
FROM sys.dm_exec_sessions
WHERE session_id = @@SPID;
GO

/*
    READ COMMITTED SNAPSHOT is usually the better default for OLTP: readers
    see the last committed version instead of blocking on writers, at the cost
    of extra tempdb traffic for the version store.

    Enabling it requires exclusive access to the database:

        ALTER DATABASE SqlRecipes SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;
*/
SELECT
    name,
    is_read_committed_snapshot_on,
    snapshot_isolation_state_desc
FROM sys.databases
WHERE name = DB_NAME();
GO

/* ------------------------------------------------------------------------- */
/* Deadlocks                                                                  */
/* ------------------------------------------------------------------------- */
/*
    A deadlock is two sessions each holding a lock the other needs. SQL Server
    kills the cheaper one with error 1205.

    The usual cause is inconsistent ordering:

        Session A: UPDATE Products ... then UPDATE Orders ...
        Session B: UPDATE Orders   ... then UPDATE Products ...

    The usual fix is not a hint or a higher isolation level. It is touching
    tables in the same order everywhere, keeping transactions short, and
    indexing the predicates so locks cover fewer rows.

    Retry only error 1205, and only for a bounded number of attempts.
*/
DECLARE @Attempt INT = 1;
DECLARE @MaxAttempts INT = 3;

WHILE @Attempt <= @MaxAttempts
BEGIN
    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE dbo.Products
        SET StockOnHand = StockOnHand + 1
        WHERE ProductId = 1;

        COMMIT TRANSACTION;
        BREAK;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        IF ERROR_NUMBER() <> 1205 OR @Attempt = @MaxAttempts
            THROW;

        SET @Attempt = @Attempt + 1;
        WAITFOR DELAY '00:00:00.100';
    END CATCH;
END;
GO

/* Deadlocks recorded by the default system_health session. */
SELECT TOP (5)
    CAST(target_data AS XML).value('(/RingBufferTarget/@truncated)[1]', 'INT') AS Truncated
FROM sys.dm_xe_session_targets AS st
INNER JOIN sys.dm_xe_sessions AS s
    ON s.address = st.event_session_address
WHERE s.name = 'system_health'
  AND st.target_name = 'ring_buffer';
GO

/* Sessions currently blocking each other. */
SELECT
    r.session_id,
    r.blocking_session_id,
    r.wait_type,
    r.wait_time,
    r.status,
    t.text AS RunningQuery
FROM sys.dm_exec_requests AS r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
WHERE r.blocking_session_id <> 0;
GO

SET XACT_ABORT OFF;
GO

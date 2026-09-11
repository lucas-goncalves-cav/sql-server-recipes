/*
    Recursive CTEs: hierarchies, date series and running structures.

    A recursive CTE has an anchor member, UNION ALL, and a recursive member
    that references the CTE itself.
*/

USE SqlRecipes;
GO

/* Walk the org chart from the top down, tracking depth and path. */
WITH OrgChart AS
(
    -- Anchor: everyone without a manager
    SELECT
        e.EmployeeId,
        e.ManagerId,
        e.FullName,
        e.JobTitle,
        0 AS Depth,
        CAST(e.FullName AS NVARCHAR(4000)) AS Path
    FROM dbo.Employees AS e
    WHERE e.ManagerId IS NULL

    UNION ALL

    -- Recursive: employees reporting to someone already in the result
    SELECT
        e.EmployeeId,
        e.ManagerId,
        e.FullName,
        e.JobTitle,
        o.Depth + 1,
        CAST(o.Path + N' > ' + e.FullName AS NVARCHAR(4000))
    FROM dbo.Employees AS e
    INNER JOIN OrgChart AS o
        ON o.EmployeeId = e.ManagerId
)
SELECT
    REPLICATE(N'    ', Depth) + FullName AS Hierarchy,
    JobTitle,
    Depth,
    Path
FROM OrgChart
ORDER BY Path;
GO

/* Everyone below a specific manager. */
DECLARE @ManagerId INT = 2;

WITH Subordinates AS
(
    SELECT e.EmployeeId, e.ManagerId, e.FullName, 1 AS Level
    FROM dbo.Employees AS e
    WHERE e.ManagerId = @ManagerId

    UNION ALL

    SELECT e.EmployeeId, e.ManagerId, e.FullName, s.Level + 1
    FROM dbo.Employees AS e
    INNER JOIN Subordinates AS s
        ON s.EmployeeId = e.ManagerId
)
SELECT * FROM Subordinates ORDER BY Level, FullName;
GO

/*
    A date series without a calendar table. Useful to report on days that had
    no activity, which a GROUP BY over the fact table can never produce.
*/
DECLARE @From DATE = DATEADD(DAY, -29, CAST(SYSUTCDATETIME() AS DATE));
DECLARE @To   DATE = CAST(SYSUTCDATETIME() AS DATE);

WITH Calendar AS
(
    SELECT @From AS [Date]

    UNION ALL

    SELECT DATEADD(DAY, 1, [Date])
    FROM Calendar
    WHERE [Date] < @To
)
SELECT
    c.[Date],
    COUNT(o.OrderId)                   AS Orders,
    ISNULL(SUM(o.TotalAmount), 0)      AS Revenue
FROM Calendar AS c
LEFT JOIN dbo.Orders AS o
    ON CAST(o.OrderDate AS DATE) = c.[Date]
GROUP BY c.[Date]
ORDER BY c.[Date]
OPTION (MAXRECURSION 365);
GO

/*
    MAXRECURSION defaults to 100. Raise it with OPTION (MAXRECURSION n), where
    n goes up to 32767, or set it to 0 for no limit. A recursive member with no
    terminating condition will otherwise run until the limit stops it.
*/

USE master;
GO

IF DB_ID('ThesisLocalTest') IS NOT NULL
BEGIN
    ALTER DATABASE ThesisLocalTest SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE ThesisLocalTest;
END
GO

CREATE DATABASE ThesisLocalTest;
GO

USE ThesisLocalTest;
GO

-- Povolení CDC na úrovni testovací databáze
EXEC sys.sp_cdc_enable_db;
GO

-- =====================================================================
-- 1. VYTVOŘENÍ STRUKTURY TABULEK (ZDROJ, ŘÍZENÍ, STAGING, DIMENZE)
-- =====================================================================
CREATE TABLE dbo.Customer (
    CustomerID       INT          CONSTRAINT PK_Customer PRIMARY KEY,
    CustomerName     VARCHAR(100) NOT NULL,
    Region           VARCHAR(50)  NOT NULL,
    Email            VARCHAR(150) NULL,
    LastModifiedDate DATETIME2    NOT NULL
);

CREATE TABLE dbo.CDC_WatermarkControl (
    TableName        VARCHAR(100) PRIMARY KEY,
    LastProcessedLSN BINARY(10)   NOT NULL,
    UpdatedAt        DATETIME2    NOT NULL
);

INSERT INTO dbo.CDC_WatermarkControl (TableName, LastProcessedLSN, UpdatedAt)
VALUES ('dbo_Customer', 0x00000000000000000000, SYSUTCDATETIME());

CREATE TABLE dbo.BatchExecutionLog (
    BatchID      INT IDENTITY(1,1) PRIMARY KEY,
    BatchName    VARCHAR(50) NOT NULL,
    FromLSN      BINARY(10)  NOT NULL,
    ToLSN        BINARY(10)  NOT NULL,
    CDCRowsRead  INT         NOT NULL,
    RowsClosed   INT         NOT NULL,
    RowsInserted INT         NOT NULL,
    Status       VARCHAR(20) NOT NULL
);

-- Emulace bronzové vrstvy (dbo_Customer_CDC)
CREATE TABLE dbo.dbo_Customer_CDC (
    StartLSN         BINARY(10)   NOT NULL,
    SeqVal           BINARY(10)   NOT NULL,
    OperationType    VARCHAR(20)  NOT NULL,
    CommitTime       DATETIME2(6) NOT NULL,
    CustomerID       INT          NOT NULL,
    CustomerName     VARCHAR(100) NOT NULL,
    Region           VARCHAR(50)  NOT NULL,
    Email            VARCHAR(150) NULL,
    LastModifiedDate DATETIME2    NOT NULL
);

-- Cílová dimenze SCD typu 2
CREATE TABLE dbo.DimCustomer (
    CustomerSK   VARCHAR(36)  PRIMARY KEY,
    CustomerID   INT          NOT NULL,
    CustomerName VARCHAR(100) NOT NULL,
    Region       VARCHAR(50)  NOT NULL,
    Email        VARCHAR(150) NULL,
    ValidFrom    DATETIME2(6) NOT NULL,
    ValidTo      DATETIME2(6) NULL,
    IsActive     BIT          NOT NULL
);

-- Aktivace CDC pro tabulku dbo.Customer
EXEC sys.sp_cdc_enable_table
    @source_schema        = N'dbo',
    @source_name          = N'Customer',
    @role_name            = NULL,
    @supports_net_changes = 1,
    @capture_instance     = N'dbo_Customer',
    @index_name           = N'PK_Customer';
GO

-- =====================================================================
-- 2. POMOCNÁ PROCEDURA PRO ZACHYCENÍ CDC (FUNGUJE S AGENTEM I BEZ NĚJ)
-- =====================================================================
CREATE OR ALTER PROCEDURE dbo.sp_FlushCDC
    @AfterLSN BINARY(10)
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1 FROM sys.dm_server_services
        WHERE servicename LIKE 'SQL Server Agent%' AND status_desc = 'Running'
    )
    BEGIN
        DECLARE @retries INT = 0;
        WHILE @retries < 20 AND NOT EXISTS (
            SELECT 1 FROM cdc.dbo_Customer_CT WHERE __$start_lsn > @AfterLSN
        )
        BEGIN
            WAITFOR DELAY '00:00:00.500';
            SET @retries += 1;
        END
    END
    ELSE
    BEGIN
        EXEC sys.sp_cdc_scan;
    END
END;
GO

-- =====================================================================
-- 3. TRANSFORMAČNÍ PROCEDURA SCD TYPU 2 (SHODNÁ S PRODUKČNÍ LOGIKOU)
-- =====================================================================
CREATE OR ALTER PROCEDURE dbo.sp_ProcessCustomerSCD2
    @RowsClosed   INT OUTPUT,
    @RowsInserted INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    -- Fáze A: Uzavření stávajících aktivních verzí v DimCustomer
    ;WITH FirstBatchEvent AS (
        SELECT
            [CustomerID],
            MIN(CASE WHEN [OperationType] = 'INSERT'
                     THEN CAST([LastModifiedDate] AS DATETIME2(6))
                     ELSE CAST([CommitTime] AS DATETIME2(6)) END) AS [FirstEventTime]
        FROM [dbo].[dbo_Customer_CDC]
        WHERE [OperationType] IN ('INSERT', 'UPDATE_AFTER', 'DELETE')
        GROUP BY [CustomerID]
    )
    UPDATE target
    SET target.[ValidTo]  = src.[FirstEventTime],
        target.[IsActive] = 0
    FROM [dbo].[DimCustomer] AS target
    INNER JOIN FirstBatchEvent AS src
        ON target.[CustomerID] = src.[CustomerID]
    WHERE target.[IsActive] = 1
      AND src.[FirstEventTime] > target.[ValidFrom];

    SET @RowsClosed = @@ROWCOUNT;

    -- Fáze B: Vložení nových verzí pro INSERT a UPDATE_AFTER (s výpočtem ValidTo přes LEAD)
    ;WITH OrderedChanges AS (
        SELECT
            [CustomerID],
            [CustomerName],
            [Region],
            [Email],
            CASE WHEN [OperationType] = 'INSERT'
                 THEN CAST([LastModifiedDate] AS DATETIME2(6))
                 ELSE CAST([CommitTime] AS DATETIME2(6)) END AS [ValidFrom],
            LEAD(CASE WHEN [OperationType] = 'INSERT'
                      THEN CAST([LastModifiedDate] AS DATETIME2(6))
                      ELSE CAST([CommitTime] AS DATETIME2(6)) END)
                OVER (PARTITION BY [CustomerID] ORDER BY [StartLSN] ASC, [SeqVal] ASC) AS [ValidTo],
            [OperationType]
        FROM [dbo].[dbo_Customer_CDC]
        WHERE [OperationType] IN ('INSERT', 'UPDATE_AFTER', 'DELETE')
    )
    INSERT INTO [dbo].[DimCustomer] (
        [CustomerSK], [CustomerID], [CustomerName], [Region], [Email], [ValidFrom], [ValidTo], [IsActive]
    )
    SELECT
        CAST(NEWID() AS VARCHAR(36)),
        [CustomerID],
        [CustomerName],
        [Region],
        [Email],
        [ValidFrom],
        [ValidTo],
        CASE WHEN [ValidTo] IS NULL THEN 1 ELSE 0 END
    FROM OrderedChanges
    WHERE [OperationType] IN ('INSERT', 'UPDATE_AFTER');

    SET @RowsInserted = @@ROWCOUNT;
END;
GO

-- =====================================================================
-- 4. SPUŠTĚNÍ VŠECH 3 TESTOVACÍCH DÁVEK (INSERT -> UPDATE -> DELETE)
-- =====================================================================
DECLARE @fromLSN BINARY(10), @toLSN BINARY(10), @cdcCount INT, @closed INT, @inserted INT;

-- ---------------------------------------------------------------------
-- DÁVKA 1: Hromadný INSERT 1 000 zákazníků + kontrolní entita ID 1001
-- ---------------------------------------------------------------------
WITH Tally AS (
    SELECT TOP (1000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
INSERT INTO dbo.Customer (CustomerID, CustomerName, Region, Email, LastModifiedDate)
SELECT
    n,
    CONCAT('Zákazník ', n),
    CASE n % 4 WHEN 0 THEN 'Praha' WHEN 1 THEN 'Brno' WHEN 2 THEN 'Ostrava' ELSE 'Plzeň' END,
    CONCAT('zakaznik', n, '@firma.cz'),
    SYSUTCDATETIME()
FROM Tally;

INSERT INTO dbo.Customer (CustomerID, CustomerName, Region, Email, LastModifiedDate)
VALUES (1001, 'Jan Novák', 'Praha', 'jan.novak@firma.cz', SYSUTCDATETIME());

SELECT @fromLSN = LastProcessedLSN FROM dbo.CDC_WatermarkControl WHERE TableName = 'dbo_Customer';
EXEC dbo.sp_FlushCDC @AfterLSN = @fromLSN;
SET @toLSN = sys.fn_cdc_get_max_lsn();

TRUNCATE TABLE dbo.dbo_Customer_CDC;
INSERT INTO dbo.dbo_Customer_CDC
SELECT ct.__$start_lsn, ct.__$seqval,
       CASE ct.__$operation WHEN 1 THEN 'DELETE' WHEN 2 THEN 'INSERT' WHEN 3 THEN 'UPDATE_BEFORE' WHEN 4 THEN 'UPDATE_AFTER' END,
       m.tran_end_time, ct.CustomerID, ct.CustomerName, ct.Region, ct.Email, ct.LastModifiedDate
FROM cdc.dbo_Customer_CT ct
JOIN cdc.lsn_time_mapping m ON ct.__$start_lsn = m.start_lsn
WHERE ct.__$start_lsn > @fromLSN AND ct.__$start_lsn <= @toLSN;
SET @cdcCount = @@ROWCOUNT;

EXEC dbo.sp_ProcessCustomerSCD2 @RowsClosed = @closed OUTPUT, @RowsInserted = @inserted OUTPUT;
UPDATE dbo.CDC_WatermarkControl SET LastProcessedLSN = @toLSN, UpdatedAt = SYSUTCDATETIME() WHERE TableName = 'dbo_Customer';
INSERT INTO dbo.BatchExecutionLog VALUES ('1. dávka (INSERT)', @fromLSN, @toLSN, @cdcCount, @closed, @inserted, 'Succeeded');

WAITFOR DELAY '00:00:01';

-- DÁVKA 2: UPDATE ID 1001 (Praha -> Brno) + 2x UPDATE ID 2 v 1 transakci
BEGIN TRANSACTION;
    UPDATE dbo.Customer
    SET Region = 'Brno', LastModifiedDate = SYSUTCDATETIME()
    WHERE CustomerID = 1001;

    UPDATE dbo.Customer
    SET Region = 'Liberec', LastModifiedDate = SYSUTCDATETIME()
    WHERE CustomerID = 2;

    UPDATE dbo.Customer
    SET Email = 'novy.kontakt2@firma.cz', LastModifiedDate = SYSUTCDATETIME()
    WHERE CustomerID = 2;
COMMIT TRANSACTION;

SELECT @fromLSN = LastProcessedLSN FROM dbo.CDC_WatermarkControl WHERE TableName = 'dbo_Customer';
EXEC dbo.sp_FlushCDC @AfterLSN = @fromLSN;
SET @toLSN = sys.fn_cdc_get_max_lsn();

TRUNCATE TABLE dbo.dbo_Customer_CDC;
INSERT INTO dbo.dbo_Customer_CDC
SELECT ct.__$start_lsn, ct.__$seqval,
       CASE ct.__$operation WHEN 1 THEN 'DELETE' WHEN 2 THEN 'INSERT' WHEN 3 THEN 'UPDATE_BEFORE' WHEN 4 THEN 'UPDATE_AFTER' END,
       m.tran_end_time, ct.CustomerID, ct.CustomerName, ct.Region, ct.Email, ct.LastModifiedDate
FROM cdc.dbo_Customer_CT ct
JOIN cdc.lsn_time_mapping m ON ct.__$start_lsn = m.start_lsn
WHERE ct.__$start_lsn > @fromLSN AND ct.__$start_lsn <= @toLSN;
SET @cdcCount = @@ROWCOUNT;

EXEC dbo.sp_ProcessCustomerSCD2 @RowsClosed = @closed OUTPUT, @RowsInserted = @inserted OUTPUT;
UPDATE dbo.CDC_WatermarkControl SET LastProcessedLSN = @toLSN, UpdatedAt = SYSUTCDATETIME() WHERE TableName = 'dbo_Customer';
INSERT INTO dbo.BatchExecutionLog VALUES ('2. dávka (UPDATE)', @fromLSN, @toLSN, @cdcCount, @closed, @inserted, 'Succeeded');

WAITFOR DELAY '00:00:01';

-- DÁVKA 3: Fyzické smazání zákazníka ID 1001 ze zdrojové tabulky
DELETE FROM dbo.Customer WHERE CustomerID = 1001;

SELECT @fromLSN = LastProcessedLSN FROM dbo.CDC_WatermarkControl WHERE TableName = 'dbo_Customer';
EXEC dbo.sp_FlushCDC @AfterLSN = @fromLSN;
SET @toLSN = sys.fn_cdc_get_max_lsn();

TRUNCATE TABLE dbo.dbo_Customer_CDC;
INSERT INTO dbo.dbo_Customer_CDC
SELECT ct.__$start_lsn, ct.__$seqval,
       CASE ct.__$operation WHEN 1 THEN 'DELETE' WHEN 2 THEN 'INSERT' WHEN 3 THEN 'UPDATE_BEFORE' WHEN 4 THEN 'UPDATE_AFTER' END,
       m.tran_end_time, ct.CustomerID, ct.CustomerName, ct.Region, ct.Email, ct.LastModifiedDate
FROM cdc.dbo_Customer_CT ct
JOIN cdc.lsn_time_mapping m ON ct.__$start_lsn = m.start_lsn
WHERE ct.__$start_lsn > @fromLSN AND ct.__$start_lsn <= @toLSN;
SET @cdcCount = @@ROWCOUNT;

EXEC dbo.sp_ProcessCustomerSCD2 @RowsClosed = @closed OUTPUT, @RowsInserted = @inserted OUTPUT;
UPDATE dbo.CDC_WatermarkControl SET LastProcessedLSN = @toLSN, UpdatedAt = SYSUTCDATETIME() WHERE TableName = 'dbo_Customer';
INSERT INTO dbo.BatchExecutionLog VALUES ('3. dávka (DELETE)', @fromLSN, @toLSN, @cdcCount, @closed, @inserted, 'Succeeded');
GO

-- VÝSTUPY PRO TABULKY

-- VÝSTUP 1: Zachycená metadata CDC pro ID 2 a 1001
SELECT
    ct.__$start_lsn AS StartLSN,
    ct.__$seqval    AS SeqVal,
    ct.__$operation AS OperationCode,
    CASE ct.__$operation
        WHEN 1 THEN 'DELETE'
        WHEN 2 THEN 'INSERT'
        WHEN 3 THEN 'UPDATE_BEFORE'
        WHEN 4 THEN 'UPDATE_AFTER'
    END AS OperationType,
    ct.CustomerID,
    ct.Region,
    ct.Email,
    m.tran_end_time AS CommitTime
FROM cdc.dbo_Customer_CT ct
JOIN cdc.lsn_time_mapping m ON ct.__$start_lsn = m.start_lsn
WHERE ct.CustomerID IN (2, 1001)
ORDER BY ct.__$start_lsn ASC, ct.__$seqval ASC;

-- VÝSTUP 2 (Tabulka Y): Vývoj verzí kontrolních entit v cílové dimenzi DimCustomer
SELECT
    CustomerSK,
    CustomerID,
    CustomerName,
    Region,
    Email,
    ValidFrom,
    ValidTo,
    IsActive
FROM dbo.DimCustomer
WHERE CustomerID IN (2, 1001)
ORDER BY CustomerID ASC, ValidFrom ASC;

-- VÝSTUP 3 (Tabulka Z): Protokol inkrementálního zpracování dávek a posun LSN
SELECT
    BatchID,
    BatchName,
    FromLSN,
    ToLSN,
    CDCRowsRead,
    RowsClosed,
    RowsInserted,
    Status
FROM dbo.BatchExecutionLog
ORDER BY BatchID ASC;

-- VÝSTUP 4 (Tabulka W): Automatizovaná kontrola všech 5 invariantů integrity (všechny chyby musí být 0)
WITH IntervalCheck AS (
    SELECT
        CustomerID,
        ValidTo,
        LEAD(ValidFrom) OVER (PARTITION BY CustomerID ORDER BY ValidFrom ASC) AS NextValidFrom
    FROM dbo.DimCustomer
)
SELECT
    (SELECT COUNT(*) FROM dbo.DimCustomer) AS CelkemRadkuVDimenzi,
    (SELECT COUNT(*) FROM dbo.DimCustomer WHERE (IsActive = 0 AND ValidTo IS NULL) OR (IsActive = 1 AND ValidTo IS NOT NULL)) AS Chyba_1_UzavreniHistorie,
    (SELECT COUNT(*) - COUNT(DISTINCT CustomerSK) FROM dbo.DimCustomer) AS Chyba_2_DuplicitniCustomerSK,
    (SELECT COUNT(*) FROM IntervalCheck WHERE NextValidFrom IS NOT NULL AND ValidTo <> NextValidFrom) AS Chyba_3_NavaznostIntervalu,
    (SELECT COUNT(*) FROM (SELECT CustomerID FROM dbo.DimCustomer WHERE IsActive = 1 GROUP BY CustomerID HAVING COUNT(*) > 1) t) AS Chyba_4_ViceAktivnichVerzi,
    (SELECT COUNT(*) FROM (
        SELECT CustomerID, CustomerName, Region, Email FROM dbo.DimCustomer WHERE IsActive = 1
        EXCEPT
        SELECT CustomerID, CustomerName, Region, Email FROM dbo.Customer
    ) t) AS Chyba_5_ShodaSeZdrojem;
GO

/* -- Volitelný úklid po zkopírování výsledků do bakalářské práce:
USE master;
ALTER DATABASE ThesisLocalTest SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE ThesisLocalTest;
*/
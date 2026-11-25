USE master;
GO

IF DB_ID('ThesisPerfBenchmark') IS NOT NULL
BEGIN
    ALTER DATABASE ThesisPerfBenchmark SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE ThesisPerfBenchmark;
END
GO

CREATE DATABASE ThesisPerfBenchmark;
GO

USE ThesisPerfBenchmark;
GO

EXEC sys.sp_cdc_enable_db;
GO

-- PŘÍPRAVA TŘÍ IDENTICKÝCH TABULEK (BASELINE / CDC / TRIGGER)
CREATE TABLE dbo.Customer_Baseline (
    CustomerID       INT          CONSTRAINT PK_Customer_Base PRIMARY KEY,
    CustomerName     VARCHAR(100) NOT NULL,
    Region           VARCHAR(50)  NOT NULL,
    Email            VARCHAR(150) NULL,
    LastModifiedDate DATETIME2    NOT NULL
);

CREATE TABLE dbo.Customer_CDC (
    CustomerID       INT          CONSTRAINT PK_Customer_CDC PRIMARY KEY,
    CustomerName     VARCHAR(100) NOT NULL,
    Region           VARCHAR(50)  NOT NULL,
    Email            VARCHAR(150) NULL,
    LastModifiedDate DATETIME2    NOT NULL
);

EXEC sys.sp_cdc_enable_table
    @source_schema        = N'dbo',
    @source_name          = N'Customer_CDC',
    @role_name            = NULL,
    @supports_net_changes = 1,
    @capture_instance     = N'dbo_Customer_CDC',
    @index_name           = N'PK_Customer_CDC';

CREATE TABLE dbo.Customer_Trigger (
    CustomerID       INT          CONSTRAINT PK_Customer_Trg PRIMARY KEY,
    CustomerName     VARCHAR(100) NOT NULL,
    Region           VARCHAR(50)  NOT NULL,
    Email            VARCHAR(150) NULL,
    LastModifiedDate DATETIME2    NOT NULL
);

CREATE TABLE dbo.Customer_Audit_Trigger (
    AuditID          BIGINT IDENTITY(1,1) PRIMARY KEY,
    OperationType    VARCHAR(10)  NOT NULL,
    ChangedAt        DATETIME2    NOT NULL DEFAULT SYSUTCDATETIME(),
    CustomerID       INT          NOT NULL,
    CustomerName     VARCHAR(100) NOT NULL,
    Region           VARCHAR(50)  NOT NULL,
    Email            VARCHAR(150) NULL,
    LastModifiedDate DATETIME2    NOT NULL
);
GO

CREATE TRIGGER dbo.trg_Customer_Audit
ON dbo.Customer_Trigger
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM inserted) AND NOT EXISTS (SELECT 1 FROM deleted)
        INSERT INTO dbo.Customer_Audit_Trigger (OperationType, CustomerID, CustomerName, Region, Email, LastModifiedDate)
        SELECT 'INSERT', CustomerID, CustomerName, Region, Email, LastModifiedDate FROM inserted;
    ELSE IF EXISTS (SELECT 1 FROM inserted) AND EXISTS (SELECT 1 FROM deleted)
        INSERT INTO dbo.Customer_Audit_Trigger (OperationType, CustomerID, CustomerName, Region, Email, LastModifiedDate)
        SELECT 'UPDATE', CustomerID, CustomerName, Region, Email, LastModifiedDate FROM inserted;
    ELSE IF EXISTS (SELECT 1 FROM deleted)
        INSERT INTO dbo.Customer_Audit_Trigger (OperationType, CustomerID, CustomerName, Region, Email, LastModifiedDate)
        SELECT 'DELETE', CustomerID, CustomerName, Region, Email, LastModifiedDate FROM deleted;
END;
GO

CREATE TABLE dbo.BenchmarkResults (
    TestScenario      VARCHAR(50)   PRIMARY KEY,
    OperationsCount   INT           NOT NULL,
    DurationMs        INT           NOT NULL,
    AvgLatencyUs      DECIMAL(10,2) NOT NULL,
    LogBytesGenerated BIGINT        NOT NULL,
    LogFlushesCount   BIGINT        NOT NULL,
    UserTriggersCount INT           NOT NULL,
    SchemaColumnsDiff INT           NOT NULL
);
GO

-- SPUŠTĚNÍ MĚŘENÍ (5 000x INSERT + 5 000x UPDATE = 10 000 OLTP TX)
SET NOCOUNT ON;

DECLARE @Iterations INT = 5000;
DECLARE @i INT, @tStart DATETIME2(6), @tEnd DATETIME2(6), @durMs INT;
DECLARE @logBytesStart BIGINT, @logBytesEnd BIGINT, @logFlushStart BIGINT, @logFlushEnd BIGINT;

-- BASELINE (bez sledování změn)
SELECT @logBytesStart = cntr_value FROM sys.dm_os_performance_counters
WHERE object_name LIKE '%:Databases%' AND instance_name = 'ThesisPerfBenchmark' AND counter_name = 'Log Bytes Flushed/sec';
SELECT @logFlushStart = cntr_value FROM sys.dm_os_performance_counters
WHERE object_name LIKE '%:Databases%' AND instance_name = 'ThesisPerfBenchmark' AND counter_name = 'Log Flushes/sec';

SET @tStart = SYSUTCDATETIME();
SET @i = 1;
WHILE @i <= @Iterations
BEGIN
    INSERT INTO dbo.Customer_Baseline VALUES (@i, CONCAT('Zákazník ', @i), 'Praha', CONCAT('user', @i, '@firma.cz'), SYSUTCDATETIME());
    SET @i += 1;
END
SET @i = 1;
WHILE @i <= @Iterations
BEGIN
    UPDATE dbo.Customer_Baseline SET Region = 'Brno', LastModifiedDate = SYSUTCDATETIME() WHERE CustomerID = @i;
    SET @i += 1;
END
SET @tEnd = SYSUTCDATETIME();

SELECT @logBytesEnd = cntr_value FROM sys.dm_os_performance_counters
WHERE object_name LIKE '%:Databases%' AND instance_name = 'ThesisPerfBenchmark' AND counter_name = 'Log Bytes Flushed/sec';
SELECT @logFlushEnd = cntr_value FROM sys.dm_os_performance_counters
WHERE object_name LIKE '%:Databases%' AND instance_name = 'ThesisPerfBenchmark' AND counter_name = 'Log Flushes/sec';

SET @durMs = DATEDIFF(MILLISECOND, @tStart, @tEnd);
INSERT INTO dbo.BenchmarkResults VALUES (
    '1. Baseline (bez sledování)', @Iterations * 2, @durMs,
    CAST(@durMs * 1000.0 / (@Iterations * 2) AS DECIMAL(10,2)),
    @logBytesEnd - @logBytesStart, @logFlushEnd - @logFlushStart,
    (SELECT COUNT(*) FROM sys.triggers WHERE parent_id = OBJECT_ID('dbo.Customer_Baseline')),
    0
);

-- NATIVNÍ ASYNCHRONNÍ CDC
SELECT @logBytesStart = cntr_value FROM sys.dm_os_performance_counters
WHERE object_name LIKE '%:Databases%' AND instance_name = 'ThesisPerfBenchmark' AND counter_name = 'Log Bytes Flushed/sec';
SELECT @logFlushStart = cntr_value FROM sys.dm_os_performance_counters
WHERE object_name LIKE '%:Databases%' AND instance_name = 'ThesisPerfBenchmark' AND counter_name = 'Log Flushes/sec';

SET @tStart = SYSUTCDATETIME();
SET @i = 1;
WHILE @i <= @Iterations
BEGIN
    INSERT INTO dbo.Customer_CDC VALUES (@i, CONCAT('Zákazník ', @i), 'Praha', CONCAT('user', @i, '@firma.cz'), SYSUTCDATETIME());
    SET @i += 1;
END
SET @i = 1;
WHILE @i <= @Iterations
BEGIN
    UPDATE dbo.Customer_CDC SET Region = 'Brno', LastModifiedDate = SYSUTCDATETIME() WHERE CustomerID = @i;
    SET @i += 1;
END
SET @tEnd = SYSUTCDATETIME();

SELECT @logBytesEnd = cntr_value FROM sys.dm_os_performance_counters
WHERE object_name LIKE '%:Databases%' AND instance_name = 'ThesisPerfBenchmark' AND counter_name = 'Log Bytes Flushed/sec';
SELECT @logFlushEnd = cntr_value FROM sys.dm_os_performance_counters
WHERE object_name LIKE '%:Databases%' AND instance_name = 'ThesisPerfBenchmark' AND counter_name = 'Log Flushes/sec';

SET @durMs = DATEDIFF(MILLISECOND, @tStart, @tEnd);
INSERT INTO dbo.BenchmarkResults VALUES (
    '2. Nativní asynchronní CDC', @Iterations * 2, @durMs,
    CAST(@durMs * 1000.0 / (@Iterations * 2) AS DECIMAL(10,2)),
    @logBytesEnd - @logBytesStart, @logFlushEnd - @logFlushStart,
    (SELECT COUNT(*) FROM sys.triggers WHERE parent_id = OBJECT_ID('dbo.Customer_CDC')),
    (SELECT COUNT(*) FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Customer_CDC')) -
    (SELECT COUNT(*) FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Customer_Baseline'))
);

-- SYNCHRONNÍ DML TRIGGER (AFTER INSERT, UPDATE, DELETE)
SELECT @logBytesStart = cntr_value FROM sys.dm_os_performance_counters
WHERE object_name LIKE '%:Databases%' AND instance_name = 'ThesisPerfBenchmark' AND counter_name = 'Log Bytes Flushed/sec';
SELECT @logFlushStart = cntr_value FROM sys.dm_os_performance_counters
WHERE object_name LIKE '%:Databases%' AND instance_name = 'ThesisPerfBenchmark' AND counter_name = 'Log Flushes/sec';

SET @tStart = SYSUTCDATETIME();
SET @i = 1;
WHILE @i <= @Iterations
BEGIN
    INSERT INTO dbo.Customer_Trigger VALUES (@i, CONCAT('Zákazník ', @i), 'Praha', CONCAT('user', @i, '@firma.cz'), SYSUTCDATETIME());
    SET @i += 1;
END
SET @i = 1;
WHILE @i <= @Iterations
BEGIN
    UPDATE dbo.Customer_Trigger SET Region = 'Brno', LastModifiedDate = SYSUTCDATETIME() WHERE CustomerID = @i;
    SET @i += 1;
END
SET @tEnd = SYSUTCDATETIME();

SELECT @logBytesEnd = cntr_value FROM sys.dm_os_performance_counters
WHERE object_name LIKE '%:Databases%' AND instance_name = 'ThesisPerfBenchmark' AND counter_name = 'Log Bytes Flushed/sec';
SELECT @logFlushEnd = cntr_value FROM sys.dm_os_performance_counters
WHERE object_name LIKE '%:Databases%' AND instance_name = 'ThesisPerfBenchmark' AND counter_name = 'Log Flushes/sec';

SET @durMs = DATEDIFF(MILLISECOND, @tStart, @tEnd);
INSERT INTO dbo.BenchmarkResults VALUES (
    '3. Synchronní DML trigger', @Iterations * 2, @durMs,
    CAST(@durMs * 1000.0 / (@Iterations * 2) AS DECIMAL(10,2)),
    @logBytesEnd - @logBytesStart, @logFlushEnd - @logFlushStart,
    (SELECT COUNT(*) FROM sys.triggers WHERE parent_id = OBJECT_ID('dbo.Customer_Trigger')),
    (SELECT COUNT(*) FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Customer_Trigger')) -
    (SELECT COUNT(*) FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Customer_Baseline'))
);

IF NOT EXISTS (SELECT 1 FROM sys.dm_server_services WHERE servicename LIKE 'SQL Server Agent%' AND status_desc = 'Running')
    EXEC sys.sp_cdc_scan;
ELSE
    WAITFOR DELAY '00:00:02';

DECLARE @BaseMs FLOAT = (SELECT DurationMs FROM dbo.BenchmarkResults WHERE TestScenario LIKE '1.%');

SELECT
    TestScenario AS Scenar,
    OperationsCount AS PocetOLTPOperaci,
    DurationMs AS CelkovyCas_ms,
    AvgLatencyUs AS PrumernaLatence_us,
    CAST((DurationMs - @BaseMs) / @BaseMs * 100.0 AS DECIMAL(6,2)) AS RezieOprotiBaseline_Procent,
    LogBytesGenerated AS ZapsanoDoLogu_Bytes,
    UserTriggersCount AS PocetTriggeruNaTabulce,
    SchemaColumnsDiff AS ZmenaStrukturyTabulky
FROM dbo.BenchmarkResults
ORDER BY TestScenario;

SELECT
    __$operation,
    CASE __$operation WHEN 2 THEN 'INSERT' WHEN 3 THEN 'UPDATE_BEFORE' WHEN 4 THEN 'UPDATE_AFTER' END AS TypOperace,
    COUNT(*) AS PocetZachycenychZaznamu
FROM cdc.dbo_Customer_CDC_CT
GROUP BY __$operation
ORDER BY __$operation;
GO
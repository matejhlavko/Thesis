USE [ThesisSourceDB];
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_GetCDCDelta]
    @CaptureInstance VARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @LastWatermarkLSN BINARY(10);
    DECLARE @MinValidLSN      BINARY(10);
    DECLARE @MaxAvailableLSN  BINARY(10);
    DECLARE @FromLSN          BINARY(10);
    DECLARE @ToLSN            BINARY(10);

    -- Load watermark
    SELECT @LastWatermarkLSN = [LastProcessedLSN]
    FROM [dbo].[CDC_WatermarkControl]
    WHERE [CaptureInstance] = @CaptureInstance;

    -- Dynamically determining LSN boundaries
    SET @MinValidLSN     = sys.fn_cdc_get_min_lsn(@CaptureInstance);
    SET @MaxAvailableLSN = sys.fn_cdc_get_max_lsn();

    IF @LastWatermarkLSN IS NULL OR @LastWatermarkLSN < @MinValidLSN
        SET @FromLSN = @MinValidLSN;
    ELSE
        SET @FromLSN = sys.fn_cdc_increment_lsn(@LastWatermarkLSN);

    SET @ToLSN = @MaxAvailableLSN;

    IF @FromLSN IS NULL OR @FromLSN > @ToLSN
    BEGIN
        PRINT 'Žádné nové CDC změny pro: ' + @CaptureInstance;
        RETURN;
    END

    -- Wrapping the CDC function name: cdc.[fn_cdc_get_all_changes_dbo_Customer]
    DECLARE @FullFunctionName NVARCHAR(256) = N'cdc.' + QUOTENAME(N'fn_cdc_get_all_changes_' + @CaptureInstance);

    DECLARE @SqlScript NVARCHAR(MAX);
    SET @SqlScript = N'
        SELECT 
            c.[__$start_lsn],
            c.[__$seqval],
            CASE c.[__$operation]
                WHEN 1 THEN ''DELETE''
                WHEN 2 THEN ''INSERT''
                WHEN 3 THEN ''UPDATE_BEFORE''
                WHEN 4 THEN ''UPDATE_AFTER''
            END AS [OperationType],
            sys.fn_cdc_map_lsn_to_time(c.[__$start_lsn]) AS [CommitTime],
            c.*
        FROM ' + @FullFunctionName + N'(@FromLSN, @ToLSN, ''all update old'') AS c
        ORDER BY c.[__$start_lsn] ASC, c.[__$seqval] ASC;
    ';

    EXEC sp_executesql 
        @SqlScript, 
        N'@FromLSN BINARY(10), @ToLSN BINARY(10)', 
        @FromLSN = @FromLSN, 
        @ToLSN = @ToLSN;
END;
GO
 USE [ThesisSourceDB];
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_GetCDCDelta]
    @CaptureInstance VARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @LastLSN BINARY(10) = NULL;
    DECLARE @MinLSN  BINARY(10) = sys.fn_cdc_get_min_lsn(@CaptureInstance);
    DECLARE @ToLSN   BINARY(10) = sys.fn_cdc_get_max_lsn();
    DECLARE @FromLSN BINARY(10);

    -- Read watermark if CDC_WatermarkControl exists
    IF OBJECT_ID(N'[dbo].[CDC_WatermarkControl]', N'U') IS NOT NULL
    BEGIN
        SELECT @LastLSN = [LastProcessedLSN]
        FROM [dbo].[CDC_WatermarkControl]
        WHERE [CaptureInstance] = @CaptureInstance;
    END

    IF @LastLSN IS NULL
        SET @FromLSN = @MinLSN;
    ELSE
        SET @FromLSN = sys.fn_cdc_increment_lsn(@LastLSN);

    IF @FromLSN < @MinLSN
        SET @FromLSN = @MinLSN;

    IF @FromLSN IS NULL OR @ToLSN IS NULL OR @FromLSN > @ToLSN
    BEGIN
        SELECT CAST(NULL AS BINARY(10)) AS [__$start_lsn] WHERE 1 = 0;
        RETURN;
    END

    DECLARE @SQL NVARCHAR(MAX) = N'
        SELECT *
        FROM [cdc].[fn_cdc_get_all_changes_' + QUOTENAME(@CaptureInstance, '') + N'](@FromLSN, @ToLSN, N''all update old'');';

    EXEC sp_executesql
        @stmt    = @SQL,
        @params  = N'@FromLSN BINARY(10), @ToLSN BINARY(10)',
        @FromLSN = @FromLSN,
        @ToLSN   = @ToLSN;
END;
GO
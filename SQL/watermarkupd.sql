USE [ThesisSourceDB];
GO

DROP PROCEDURE IF EXISTS [dbo].[sp_UpdateCDCWatermark];
GO

CREATE PROCEDURE [dbo].[sp_UpdateCDCWatermark]
    @CaptureInstance VARCHAR(100),
    @HighWatermarkLSN BINARY(10)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE [dbo].[CDC_WatermarkControl]
    SET [LastProcessedLSN]  = @HighWatermarkLSN,
        [LastProcessedTime] = sys.fn_cdc_map_lsn_to_time(@HighWatermarkLSN),
        [UpdatedUtc]        = SYSUTCDATETIME()
    WHERE [CaptureInstance] = @CaptureInstance;
END;
GO
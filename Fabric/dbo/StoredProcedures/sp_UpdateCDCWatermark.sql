-- WATERMARK UPDATE

CREATE   PROCEDURE [dbo].[sp_UpdateCDCWatermark]
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE w
    SET w.[LastProcessedLSN]  = COALESCE(src.[MaxLSN], w.[LastProcessedLSN]),
        w.[LastProcessedTime] = COALESCE(CAST(src.[MaxTime] AS DATETIME2(6)), w.[LastProcessedTime]),
        w.[UpdatedUtc]        = SYSUTCDATETIME()
    FROM [dbo].[CDC_WatermarkControl] AS w
    CROSS JOIN (
        SELECT
            CONVERT(VARCHAR(22), MAX(ct.[__$start_lsn]), 1) AS MaxLSN,
            MAX(m.[tran_end_time])                          AS MaxTime
        FROM [Thesis_Lakehouse].[cdc].[dbo_Customer_CT] AS ct
        LEFT JOIN [Thesis_Lakehouse].[cdc].[lsn_time_mapping] AS m
            ON ct.[__$start_lsn] = m.[start_lsn]
    ) AS src
    WHERE w.[CaptureInstance] = 'dbo_Customer'
      AND src.[MaxLSN] IS NOT NULL;

    UPDATE w
    SET w.[LastProcessedLSN]  = COALESCE(src.[MaxLSN], w.[LastProcessedLSN]),
        w.[LastProcessedTime] = COALESCE(CAST(src.[MaxTime] AS DATETIME2(6)), w.[LastProcessedTime]),
        w.[UpdatedUtc]        = SYSUTCDATETIME()
    FROM [dbo].[CDC_WatermarkControl] AS w
    CROSS JOIN (
        SELECT
            CONVERT(VARCHAR(22), MAX(ct.[__$start_lsn]), 1) AS MaxLSN,
            MAX(m.[tran_end_time])                          AS MaxTime
        FROM [Thesis_Lakehouse].[cdc].[dbo_Product_CT] AS ct
        LEFT JOIN [Thesis_Lakehouse].[cdc].[lsn_time_mapping] AS m
            ON ct.[__$start_lsn] = m.[start_lsn]
    ) AS src
    WHERE w.[CaptureInstance] = 'dbo_Product'
      AND src.[MaxLSN] IS NOT NULL;

    UPDATE w
    SET w.[LastProcessedLSN]  = COALESCE(src.[MaxLSN], w.[LastProcessedLSN]),
        w.[LastProcessedTime] = COALESCE(CAST(src.[MaxTime] AS DATETIME2(6)), w.[LastProcessedTime]),
        w.[UpdatedUtc]        = SYSUTCDATETIME()
    FROM [dbo].[CDC_WatermarkControl] AS w
    CROSS JOIN (
        SELECT
            CONVERT(VARCHAR(22), MAX(ct.[__$start_lsn]), 1) AS MaxLSN,
            MAX(m.[tran_end_time])                          AS MaxTime
        FROM [Thesis_Lakehouse].[cdc].[dbo_SalesOrder_CT] AS ct
        LEFT JOIN [Thesis_Lakehouse].[cdc].[lsn_time_mapping] AS m
            ON ct.[__$start_lsn] = m.[start_lsn]
    ) AS src
    WHERE w.[CaptureInstance] = 'dbo_SalesOrder'
      AND src.[MaxLSN] IS NOT NULL;
END;

GO
CREATE   PROCEDURE [dbo].[sp_ProcessProductSCD2]
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. Close active DimProduct versions when a newer CDC event exists
    UPDATE target
    SET target.[ValidTo]  = src.[NextChangeTime],
        target.[IsActive] = 0
    FROM [dbo].[DimProduct] AS target
    INNER JOIN (
        SELECT
            d.[ProductSK],
            MIN(dedup.[EventTime]) AS [NextChangeTime]
        FROM [dbo].[DimProduct] AS d
        INNER JOIN (
            SELECT
                ct.[ProductID],
                CASE WHEN ct.[__$operation] = 2
                     THEN CAST(ct.[LastModifiedDate] AS DATETIME2(6))
                     ELSE COALESCE(
                         DATEADD(HOUR, -1, CAST(m.[tran_end_time] AS DATETIME2(6))),
                         CAST(ct.[LastModifiedDate] AS DATETIME2(6))
                     ) END AS [EventTime],
                ROW_NUMBER() OVER (
                    PARTITION BY ct.[__$start_lsn], ct.[__$seqval]
                    ORDER BY ct.[__$start_lsn]
                ) AS [dup_rn]
            FROM [Thesis_Lakehouse].[cdc].[dbo_Product_CT] AS ct
            LEFT JOIN [Thesis_Lakehouse].[cdc].[lsn_time_mapping] AS m
                ON ct.[__$start_lsn] = m.[start_lsn]
            WHERE ct.[__$operation] IN (1, 2, 4)
        ) AS dedup
            ON d.[ProductID] = dedup.[ProductID]
        WHERE d.[IsActive] = 1
          AND dedup.[dup_rn] = 1
          AND dedup.[EventTime] > d.[ValidFrom]
        GROUP BY d.[ProductSK]
    ) AS src
        ON target.[ProductSK] = src.[ProductSK];

    -- 2. Insert deduplicated INSERT / UPDATE_AFTER versions with chained ValidTo
    INSERT INTO [dbo].[DimProduct] (
        [ProductSK], [ProductID], [ProductName], [Category], [UnitPrice], [ValidFrom], [ValidTo], [IsActive]
    )
    SELECT
        CAST(NEWID() AS VARCHAR(36)),
        p.[ProductID],
        p.[ProductName],
        p.[Category],
        p.[UnitPrice],
        p.[EventTime],
        p.[NextEventTime],
        CASE WHEN p.[NextEventTime] IS NULL THEN 1 ELSE 0 END
    FROM (
        SELECT
            dedup.[ProductID],
            dedup.[ProductName],
            dedup.[Category],
            dedup.[UnitPrice],
            dedup.[__$operation],
            dedup.[EventTime],
            LEAD(dedup.[EventTime]) OVER (
                PARTITION BY dedup.[ProductID]
                ORDER BY dedup.[__$start_lsn], dedup.[__$seqval]
            ) AS [NextEventTime]
        FROM (
            SELECT
                ct.[__$start_lsn],
                ct.[__$seqval],
                ct.[__$operation],
                ct.[ProductID],
                ct.[ProductName],
                ct.[Category],
                ct.[UnitPrice],
                CASE WHEN ct.[__$operation] = 2
                     THEN CAST(ct.[LastModifiedDate] AS DATETIME2(6))
                     ELSE COALESCE(
                         DATEADD(HOUR, -1, CAST(m.[tran_end_time] AS DATETIME2(6))),
                         CAST(ct.[LastModifiedDate] AS DATETIME2(6))
                     ) END AS [EventTime],
                ROW_NUMBER() OVER (
                    PARTITION BY ct.[__$start_lsn], ct.[__$seqval]
                    ORDER BY ct.[__$start_lsn]
                ) AS [dup_rn]
            FROM [Thesis_Lakehouse].[cdc].[dbo_Product_CT] AS ct
            LEFT JOIN [Thesis_Lakehouse].[cdc].[lsn_time_mapping] AS m
                ON ct.[__$start_lsn] = m.[start_lsn]
            WHERE ct.[__$operation] IN (1, 2, 4)
        ) AS dedup
        WHERE dedup.[dup_rn] = 1
    ) AS p
    WHERE p.[__$operation] IN (2, 4)
      AND NOT EXISTS (
          SELECT 1 FROM [dbo].[DimProduct] AS d
          WHERE d.[ProductID] = p.[ProductID] AND d.[ValidFrom] = p.[EventTime]
      );
END;

GO
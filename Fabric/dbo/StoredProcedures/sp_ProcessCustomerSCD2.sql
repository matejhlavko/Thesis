CREATE   PROCEDURE [dbo].[sp_ProcessCustomerSCD2]
AS
BEGIN
    SET NOCOUNT ON;

    -- Close DimCustomer versions when new CDC exists
    UPDATE target
    SET target.[ValidTo]  = src.[NextChangeTime],
        target.[IsActive] = 0
    FROM [dbo].[DimCustomer] AS target
    INNER JOIN (
        SELECT
            d.[CustomerSK],
            MIN(dedup.[EventTime]) AS [NextChangeTime]
        FROM [dbo].[DimCustomer] AS d
        INNER JOIN (
            SELECT
                ct.[CustomerID],
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
            FROM [Thesis_Lakehouse].[cdc].[dbo_Customer_CT] AS ct
            LEFT JOIN [Thesis_Lakehouse].[cdc].[lsn_time_mapping] AS m
                ON ct.[__$start_lsn] = m.[start_lsn]
            WHERE ct.[__$operation] IN (1, 2, 4)
        ) AS dedup
            ON d.[CustomerID] = dedup.[CustomerID]
        WHERE d.[IsActive] = 1
          AND dedup.[dup_rn] = 1
          AND dedup.[EventTime] > d.[ValidFrom]
        GROUP BY d.[CustomerSK]
    ) AS src
        ON target.[CustomerSK] = src.[CustomerSK];

    -- INSERT/UPDATE_AFTER versions with ValidTo
    INSERT INTO [dbo].[DimCustomer] (
        [CustomerSK], [CustomerID], [CustomerName], [Region], [Email], [ValidFrom], [ValidTo], [IsActive]
    )
    SELECT
        CAST(NEWID() AS VARCHAR(36)),
        c.[CustomerID],
        c.[CustomerName],
        c.[Region],
        c.[Email],
        c.[EventTime],
        c.[NextEventTime],
        CASE WHEN c.[NextEventTime] IS NULL THEN 1 ELSE 0 END
    FROM (
        SELECT
            dedup.[CustomerID],
            dedup.[CustomerName],
            dedup.[Region],
            dedup.[Email],
            dedup.[__$operation],
            dedup.[EventTime],
            LEAD(dedup.[EventTime]) OVER (
                PARTITION BY dedup.[CustomerID]
                ORDER BY dedup.[__$start_lsn], dedup.[__$seqval]
            ) AS [NextEventTime]
        FROM (
            SELECT
                ct.[__$start_lsn],
                ct.[__$seqval],
                ct.[__$operation],
                ct.[CustomerID],
                ct.[CustomerName],
                ct.[Region],
                ct.[Email],
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
            FROM [Thesis_Lakehouse].[cdc].[dbo_Customer_CT] AS ct
            LEFT JOIN [Thesis_Lakehouse].[cdc].[lsn_time_mapping] AS m
                ON ct.[__$start_lsn] = m.[start_lsn]
            WHERE ct.[__$operation] IN (1, 2, 4)
        ) AS dedup
        WHERE dedup.[dup_rn] = 1
    ) AS c
    WHERE c.[__$operation] IN (2, 4)
      AND NOT EXISTS (
          SELECT 1 FROM [dbo].[DimCustomer] AS d
          WHERE d.[CustomerID] = c.[CustomerID] AND d.[ValidFrom] = c.[EventTime]
      );
END;

GO

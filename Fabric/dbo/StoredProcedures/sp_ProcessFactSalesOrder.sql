CREATE   PROCEDURE [dbo].[sp_ProcessFactSalesOrder]
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE target
    SET target.[Quantity]         = src.[Quantity],
        target.[TotalAmount]      = src.[TotalAmount],
        target.[OrderStatus]      = src.[OrderStatus],
        target.[LastModifiedDate] = src.[LastModifiedDate]
    FROM [dbo].[FactSalesOrder] AS target
    INNER JOIN (
        SELECT
            [OrderID],
            [Quantity],
            [TotalAmount],
            [OrderStatus],
            CAST([LastModifiedDate] AS DATETIME2(6)) AS [LastModifiedDate],
            ROW_NUMBER() OVER (PARTITION BY [OrderID] ORDER BY [__$start_lsn] DESC, [__$seqval] DESC) AS [rn]
        FROM [Thesis_Lakehouse].[cdc].[dbo_SalesOrder_CT]
        WHERE [__$operation] IN (2, 4)
    ) AS src
        ON target.[OrderID] = src.[OrderID]
    WHERE src.[rn] = 1;

    INSERT INTO [dbo].[FactSalesOrder] (
        [OrderSK], [OrderID], [CustomerSK], [ProductSK], [Quantity], [TotalAmount], [OrderStatus], [OrderDate], [LastModifiedDate]
    )
    SELECT
        CAST(NEWID() AS VARCHAR(36)),
        s.[OrderID],
        c.[CustomerSK],
        p.[ProductSK],
        s.[Quantity],
        s.[TotalAmount],
        s.[OrderStatus],
        s.[OrderDate],
        s.[LastModifiedDate]
    FROM (
        SELECT
            [OrderID],
            [CustomerID],
            [ProductID],
            [Quantity],
            [TotalAmount],
            [OrderStatus],
            CAST([OrderDate] AS DATETIME2(6))        AS [OrderDate],
            CAST([LastModifiedDate] AS DATETIME2(6)) AS [LastModifiedDate],
            ROW_NUMBER() OVER (PARTITION BY [OrderID] ORDER BY [__$start_lsn] DESC, [__$seqval] DESC) AS [rn]
        FROM [Thesis_Lakehouse].[cdc].[dbo_SalesOrder_CT]
        WHERE [__$operation] IN (2, 4)
    ) AS s
    INNER JOIN [dbo].[DimCustomer] AS c
        ON s.[CustomerID] = c.[CustomerID]
        AND s.[OrderDate] >= c.[ValidFrom]
        AND (s.[OrderDate] < c.[ValidTo] OR c.[ValidTo] IS NULL)
    INNER JOIN [dbo].[DimProduct] AS p
        ON s.[ProductID] = p.[ProductID]
        AND s.[OrderDate] >= p.[ValidFrom]
        AND (s.[OrderDate] < p.[ValidTo] OR p.[ValidTo] IS NULL)
    WHERE s.[rn] = 1
      AND NOT EXISTS (
          SELECT 1 FROM [dbo].[FactSalesOrder] AS f WHERE f.[OrderID] = s.[OrderID]
      );
END;

GO
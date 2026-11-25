CREATE
      PROCEDURE [dbo].[sp_LoadFactOrders] AS BEGIN
SET NOCOUNT
        ON;
INSERT
INTO [dbo].[FactOrders] ([OrderSK], [OrderID], [CustomerSK], [OrderDate], [TotalAmount], [OrderStatus])
SELECT
    NEWID () AS [OrderSK],
    stg.[OrderID],
    dim.[CustomerSK],
    stg.[OrderDate],
    stg.[TotalAmount],
    stg.[OrderStatus]
FROM [dbo].[StgOrders] stg
    INNER JOIN [dbo].[DimCustomer] dim
        ON stg.[CustomerID] = dim.[CustomerID]
    AND stg.[OrderDate] >= dim.[ValidFrom]
    AND (stg.[OrderDate] < dim.[ValidTo] OR dim.[ValidTo] IS NULL)
WHERE NOT EXISTS (
SELECT 1
FROM [dbo].[FactOrders] f
WHERE f.[OrderID] = stg.[OrderID]); END;

GO
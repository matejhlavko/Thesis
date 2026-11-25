USE [ThesisSourceDB];
GO

DECLARE @CustJakub INT, @CustKarolina INT, @ProdMouse INT;

--INSERT
INSERT INTO [dbo].[Customer] ([CustomerName], [Region], [Email])
VALUES ('Jakub Horák', 'Hradec Králové', 'jakub.horak@example.cz');
SET @CustJakub = SCOPE_IDENTITY();

INSERT INTO [dbo].[Customer] ([CustomerName], [Region], [Email])
VALUES ('Karolína Benešová', 'Brno', 'karolina.benesova@example.cz');
SET @CustKarolina = SCOPE_IDENTITY();

INSERT INTO [dbo].[Product] ([ProductName], [Category], [UnitPrice])
VALUES ('Logitech MX Master 3S', 'Accessories', 2490.00);
SET @ProdMouse = SCOPE_IDENTITY();

INSERT INTO [dbo].[SalesOrder] ([CustomerID], [ProductID], [Quantity], [TotalAmount], [OrderStatus])
VALUES
    (@CustJakub, @ProdMouse, 2, 4980.00, 'Completed'),
    (@CustKarolina, 1, 1, 42990.00, 'Processing');
GO

WAITFOR DELAY '00:00:01';
GO

-- UPDATE
UPDATE [dbo].[Customer]
SET [Region] = 'Praha', [Email] = 'jan.novak.praha@example.cz', [LastModifiedDate] = SYSUTCDATETIME()
WHERE [CustomerID] = 1;

UPDATE [dbo].[Customer]
SET [Region] = 'České Budějovice', [LastModifiedDate] = SYSUTCDATETIME()
WHERE [CustomerID] = 5;

UPDATE [dbo].[Product]
SET [UnitPrice] = 39990.00, [LastModifiedDate] = SYSUTCDATETIME()
WHERE [ProductID] = 1;

UPDATE [dbo].[Product]
SET [UnitPrice] = 8990.00, [LastModifiedDate] = SYSUTCDATETIME()
WHERE [ProductID] = 2;

UPDATE [dbo].[SalesOrder]
SET [OrderStatus] = 'Delivered', [LastModifiedDate] = SYSUTCDATETIME()
WHERE [OrderID] IN (2, 4);
GO

-- DELETE
DELETE FROM [dbo].[SalesOrder] WHERE [CustomerID] = 7;
DELETE FROM [dbo].[Customer]   WHERE [CustomerID] = 7;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.dm_server_services
    WHERE servicename LIKE 'SQL Server Agent%' AND status_desc = 'Running'
)
    EXEC sys.sp_cdc_scan;
ELSE
    WAITFOR DELAY '00:00:06';
GO

-- Preview
EXEC [dbo].[sp_GetCDCDelta] @CaptureInstance = 'dbo_Customer';
EXEC [dbo].[sp_GetCDCDelta] @CaptureInstance = 'dbo_Product';
EXEC [dbo].[sp_GetCDCDelta] @CaptureInstance = 'dbo_SalesOrder';
GO
USE [ThesisSourceDB];
GO

-- Import data
INSERT INTO [dbo].[Customer] ([CustomerName], [Region], [Email]) 
VALUES 
    ('Jan Novák', 'Hradec Králové', 'jan.novak@example.cz'),
    ('Eva Dvořáková', 'Brno', 'eva.dvorakova@example.cz'),
    ('Karel Malý', 'Ostrava', 'karel.maly@example.cz');

INSERT INTO [dbo].[Product] ([ProductName], [Category], [UnitPrice])
VALUES 
    ('Dell XPS 15 Laptop', 'Electronics', 45000.00),
    ('Ergonomic Office Chair', 'Furniture', 8500.00);

INSERT INTO [dbo].[SalesOrder] ([CustomerID], [ProductID], [Quantity], [TotalAmount], [OrderStatus])
VALUES 
    (1, 1, 1, 45000.00, 'Completed'),
    (2, 2, 2, 17000.00, 'Processing');
GO

-- DML modification (Update and Delete)
UPDATE [dbo].[Customer]   SET [Region] = 'Pardubice' WHERE [CustomerID] = 1;
UPDATE [dbo].[Product]    SET [UnitPrice] = 42990.00 WHERE [ProductID] = 1;
UPDATE [dbo].[SalesOrder] SET [OrderStatus] = 'Shipped' WHERE [OrderID] = 2;
DELETE FROM [dbo].[Customer] WHERE [CustomerID] = 3;
GO

-- Wait 2 seconds for transaction log reader
WAITFOR DELAY '00:00:02';

-- Extract delta for each table
EXEC [dbo].[sp_GetCDCDelta] @CaptureInstance = 'dbo_Customer';
EXEC [dbo].[sp_GetCDCDelta] @CaptureInstance = 'dbo_Product';
EXEC [dbo].[sp_GetCDCDelta] @CaptureInstance = 'dbo_SalesOrder';
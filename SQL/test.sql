USE [ThesisSourceDB];
GO

-- Import data
INSERT INTO [dbo].[Customer] ([CustomerName], [Region], [Email]) 
VALUES 
    ('Jan Novák', 'Hradec Králové', 'jan.novak@example.cz'),
    ('Eva Dvořáková', 'Brno', 'eva.dvorakova@example.cz'),
    ('Karel Malý', 'Ostrava', 'karel.maly@example.cz'),
    ('Lucie Svobodová', 'Praha', 'lucie.svobodova@example.cz'),
    ('Petr Černý', 'Plzeň', 'petr.cerny@example.cz'),
    ('Tereza Kučerová', 'Liberec', 'tereza.kucerova@example.cz'),
    ('Martin Procházka', 'Olomouc', 'martin.prochazka@example.cz'),
    ('Tomáš Veselý', 'České Budějovice', 'tomas.vesely@example.cz');

INSERT INTO [dbo].[Product] ([ProductName], [Category], [UnitPrice])
VALUES 
    ('Dell XPS 15 Laptop', 'Electronics', 45000.00),
    ('Ergonomic Office Chair', 'Furniture', 8500.00),
    ('LG UltraGear 27" Monitor', 'Electronics', 9200.00),
    ('Mechanical Keyboard', 'Accessories', 3400.00),
    ('Standing Desk 160x80', 'Furniture', 12500.00),
    ('USB-C Docking Station', 'Accessories', 4100.00);

INSERT INTO [dbo].[SalesOrder] ([CustomerID], [ProductID], [Quantity], [TotalAmount], [OrderStatus])
VALUES 
    (1, 1, 1, 45000.00, 'Completed'),
    (2, 2, 2, 17000.00, 'Processing'),
    (4, 3, 2, 18400.00, 'Completed'),
    (4, 4, 1, 3400.00, 'Processing'),
    (5, 5, 1, 12500.00, 'Shipped'),
    (6, 1, 1, 45000.00, 'Processing'),
    (7, 3, 1, 9200.00, 'Cancelled'),
    (5, 4, 3, 10200.00, 'Completed');
GO

-- DML modifications (Update and Delete)
UPDATE [dbo].[Customer]   SET [Region] = 'Pardubice' WHERE [CustomerID] = 1;
UPDATE [dbo].[Customer]   SET [Region] = 'Praha', [Email] = 'eva.novakova@example.cz' WHERE [CustomerID] = 2;
UPDATE [dbo].[Customer]   SET [Region] = 'Zlín' WHERE [CustomerID] = 4;
UPDATE [dbo].[Customer]   SET [Email] = 'l.svobodova@firma.cz' WHERE [CustomerID] = 4;
DELETE FROM [dbo].[Customer] WHERE [CustomerID] IN (3, 8);

UPDATE [dbo].[Product]    SET [UnitPrice] = 42990.00 WHERE [ProductID] = 1;
UPDATE [dbo].[Product]    SET [UnitPrice] = 8790.00 WHERE [ProductID] = 3;
UPDATE [dbo].[Product]    SET [Category] = 'Office Furniture', [UnitPrice] = 11900.00 WHERE [ProductID] = 5;
DELETE FROM [dbo].[Product] WHERE [ProductID] = 6;

UPDATE [dbo].[SalesOrder] SET [OrderStatus] = 'Shipped' WHERE [OrderID] = 2;
UPDATE [dbo].[SalesOrder] SET [OrderStatus] = 'Completed' WHERE [OrderID] = 4;
UPDATE [dbo].[SalesOrder] SET [Quantity] = 2, [TotalAmount] = 85980.00, [OrderStatus] = 'Shipped' WHERE [OrderID] = 6;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.dm_server_services
    WHERE servicename LIKE 'SQL Server Agent%' AND status_desc = 'Running'
)
    EXEC sys.sp_cdc_scan;
ELSE
    WAITFOR DELAY '00:00:06';
GO

-- Extract delta
EXEC [dbo].[sp_GetCDCDelta] @CaptureInstance = 'dbo_Customer';
EXEC [dbo].[sp_GetCDCDelta] @CaptureInstance = 'dbo_Product';
EXEC [dbo].[sp_GetCDCDelta] @CaptureInstance = 'dbo_SalesOrder';
GO

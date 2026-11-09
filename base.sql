USE [ThesisSourceDB];
GO

-- Clean environment reset
EXEC sys.sp_cdc_disable_table @source_schema = N'dbo', @source_name = N'SalesOrder', @capture_instance = N'all';
EXEC sys.sp_cdc_disable_table @source_schema = N'dbo', @source_name = N'Product',    @capture_instance = N'all';
EXEC sys.sp_cdc_disable_table @source_schema = N'dbo', @source_name = N'Customer',   @capture_instance = N'all';

DROP TABLE IF EXISTS [dbo].[SalesOrder];
DROP TABLE IF EXISTS [dbo].[Product];
DROP TABLE IF EXISTS [dbo].[Customer];
DROP TABLE IF EXISTS [dbo].[CDC_WatermarkControl];
GO

-- Customer Dimension Table
CREATE TABLE [dbo].[Customer] (
    [CustomerID]       INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Customer PRIMARY KEY CLUSTERED,
    [CustomerName]     VARCHAR(100)      NOT NULL,
    [Region]           VARCHAR(50)       NOT NULL,
    [Email]            VARCHAR(150)      NULL,
    [LastModifiedDate] DATETIME2(7)      NOT NULL CONSTRAINT DF_Customer_LastModified DEFAULT SYSUTCDATETIME()
);

-- Product Dimension Table
CREATE TABLE [dbo].[Product] (
    [ProductID]        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Product PRIMARY KEY CLUSTERED,
    [ProductName]      VARCHAR(100)      NOT NULL,
    [Category]         VARCHAR(50)       NOT NULL,
    [UnitPrice]        DECIMAL(18,2)     NOT NULL,
    [LastModifiedDate] DATETIME2(7)      NOT NULL CONSTRAINT DF_Product_LastModified DEFAULT SYSUTCDATETIME()
);

-- SalesOrder Transaction Table
CREATE TABLE [dbo].[SalesOrder] (
    [OrderID]          INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_SalesOrder PRIMARY KEY CLUSTERED,
    [CustomerID]       INT               NOT NULL CONSTRAINT FK_SalesOrder_Customer FOREIGN KEY REFERENCES [dbo].[Customer]([CustomerID]),
    [ProductID]        INT               NOT NULL CONSTRAINT FK_SalesOrder_Product  FOREIGN KEY REFERENCES [dbo].[Product]([ProductID]),
    [Quantity]         INT               NOT NULL,
    [TotalAmount]      DECIMAL(18,2)     NOT NULL,
    [OrderStatus]      VARCHAR(20)       NOT NULL,
    [OrderDate]        DATETIME2(7)      NOT NULL CONSTRAINT DF_SalesOrder_Date DEFAULT SYSUTCDATETIME(),
    [LastModifiedDate] DATETIME2(7)      NOT NULL CONSTRAINT DF_SalesOrder_LastModified DEFAULT SYSUTCDATETIME()
);
GO

-- Enable Database CDC if not active
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = N'ThesisSourceDB' AND is_cdc_enabled = 0)
BEGIN
    EXEC sys.sp_cdc_enable_db;
END
GO

-- Enable CDC for each table
EXEC sys.sp_cdc_enable_table
    @source_schema = N'dbo', @source_name = N'Customer', @role_name = NULL,
    @supports_net_changes = 1, @capture_instance = N'dbo_Customer', @index_name = N'PK_Customer';

EXEC sys.sp_cdc_enable_table
    @source_schema = N'dbo', @source_name = N'Product', @role_name = NULL,
    @supports_net_changes = 1, @capture_instance = N'dbo_Product', @index_name = N'PK_Product';

EXEC sys.sp_cdc_enable_table
    @source_schema = N'dbo', @source_name = N'SalesOrder', @role_name = NULL,
    @supports_net_changes = 1, @capture_instance = N'dbo_SalesOrder', @index_name = N'PK_SalesOrder';
GO

-- Entity Watermark Control Table
CREATE TABLE [dbo].[CDC_WatermarkControl] (
    [CaptureInstance]   VARCHAR(100) NOT NULL CONSTRAINT PK_CDC_WatermarkControl PRIMARY KEY,
    [LastProcessedLSN]  BINARY(10)   NULL,
    [LastProcessedTime] DATETIME2(7) NULL,
    [UpdatedUtc]        DATETIME2(7) NOT NULL CONSTRAINT DF_CDC_Watermark_Updated DEFAULT SYSUTCDATETIME()
);

INSERT INTO [dbo].[CDC_WatermarkControl] ([CaptureInstance], [LastProcessedLSN], [LastProcessedTime])
VALUES 
    ('dbo_Customer', NULL, NULL),
    ('dbo_Product', NULL, NULL),
    ('dbo_SalesOrder', NULL, NULL);
GO
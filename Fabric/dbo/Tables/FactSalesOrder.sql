CREATE TABLE [dbo].[FactSalesOrder] (
    [OrderSK]          VARCHAR (36)    NOT NULL,
    [OrderID]          INT             NOT NULL,
    [CustomerSK]       VARCHAR (36)    NOT NULL,
    [ProductSK]        VARCHAR (36)    NOT NULL,
    [Quantity]         INT             NOT NULL,
    [TotalAmount]      DECIMAL (18, 2) NOT NULL,
    [OrderStatus]      VARCHAR (20)    NOT NULL,
    [OrderDate]        DATETIME2 (6)   NOT NULL,
    [LastModifiedDate] DATETIME2 (6)   NOT NULL
);


GO
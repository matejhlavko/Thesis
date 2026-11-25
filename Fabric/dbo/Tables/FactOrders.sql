CREATE TABLE [dbo].[FactOrders] (
    [OrderSK]     VARCHAR (36)    NOT NULL,
    [OrderID]     INT             NOT NULL,
    [CustomerSK]  VARCHAR (36)    NOT NULL,
    [OrderDate]   DATETIME2 (6)   NOT NULL,
    [TotalAmount] DECIMAL (18, 2) NOT NULL,
    [OrderStatus] VARCHAR (50)    NOT NULL
);


GO
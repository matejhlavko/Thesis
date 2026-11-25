CREATE TABLE [dbo].[StgOrders] (
    [OrderID]     INT             NOT NULL,
    [CustomerID]  INT             NOT NULL,
    [OrderDate]   DATETIME2 (6)   NOT NULL,
    [TotalAmount] DECIMAL (18, 2) NOT NULL,
    [OrderStatus] VARCHAR (50)    NOT NULL
);


GO
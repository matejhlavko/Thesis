CREATE TABLE [dbo].[DimProduct] (
    [ProductSK]   VARCHAR (36)    NOT NULL,
    [ProductID]   INT             NOT NULL,
    [ProductName] VARCHAR (100)   NOT NULL,
    [Category]    VARCHAR (50)    NOT NULL,
    [UnitPrice]   DECIMAL (18, 2) NOT NULL,
    [ValidFrom]   DATETIME2 (6)   NOT NULL,
    [ValidTo]     DATETIME2 (6)   NULL,
    [IsActive]    BIT             NOT NULL
);


GO
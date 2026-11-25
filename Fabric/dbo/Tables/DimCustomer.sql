CREATE TABLE [dbo].[DimCustomer] (
    [CustomerSK]   VARCHAR (36)  NOT NULL,
    [CustomerID]   INT           NOT NULL,
    [CustomerName] VARCHAR (100) NOT NULL,
    [Region]       VARCHAR (50)  NOT NULL,
    [Email]        VARCHAR (150) NULL,
    [ValidFrom]    DATETIME2 (6) NOT NULL,
    [ValidTo]      DATETIME2 (6) NULL,
    [IsActive]     BIT           NOT NULL
);


GO
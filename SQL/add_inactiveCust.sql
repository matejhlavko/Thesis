USE [ThesisSourceDB];
GO

DECLARE @InactiveCust1 INT, @InactiveCust2 INT;

-- Insert
INSERT INTO [dbo].[Customer] ([CustomerName], [Region], [Email])
VALUES ('Ondřej Fiala', 'Zlín', 'ondrej.fiala@example.cz');
SET @InactiveCust1 = SCOPE_IDENTITY();

INSERT INTO [dbo].[Customer] ([CustomerName], [Region], [Email])
VALUES ('Veronika Marková', 'Karlovy Vary', 'veronika.markova@example.cz');
SET @InactiveCust2 = SCOPE_IDENTITY();

WAITFOR DELAY '00:00:01';

DELETE FROM [dbo].[Customer]
WHERE [CustomerID] IN (@InactiveCust1, @InactiveCust2);
GO
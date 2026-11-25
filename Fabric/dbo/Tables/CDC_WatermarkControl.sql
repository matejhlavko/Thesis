CREATE TABLE [dbo].[CDC_WatermarkControl] (
    [CaptureInstance]   VARCHAR (100) NOT NULL,
    [LastProcessedLSN]  VARCHAR (22)  NOT NULL,
    [LastProcessedTime] DATETIME2 (6) NULL,
    [UpdatedUtc]        DATETIME2 (6) NOT NULL
);


GO

ALTER TABLE [dbo].[CDC_WatermarkControl]
    ADD CONSTRAINT [PK_CDC_WatermarkControl] PRIMARY KEY NONCLUSTERED ([CaptureInstance] ASC) NOT ENFORCED;


GO
-- 094: dw.factMeteoDaily -- hecho Gold (SCD Tipo 1), a partir de
-- [int].factMeteoDaily.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'factMeteoDaily'
)
BEGIN
    CREATE TABLE dw.factMeteoDaily (
        MeteoDailyKey     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_factMeteoDaily PRIMARY KEY,
        Site              NVARCHAR(40)  NOT NULL,
        MeasuredDate      DATE          NOT NULL,
        GhiRealWhM2       DECIMAL(9,2)  NULL,
        HsfRealHrs        DECIMAL(5,2)  NULL,
        WindSpeedRealMps  DECIMAL(5,2)  NULL,
        Source            NVARCHAR(100) NOT NULL,
        SourceVersion     NVARCHAR(100) NULL,
        RetrievedAt       DATETIME2(7)  NOT NULL,
        SourceLoadedAt    DATETIME2(7)  NULL,
        EsVigente         BIT           NOT NULL CONSTRAINT DF_dw_factMeteoDaily_EsVigente DEFAULT (1),
        HashDiff          BINARY(32)    NOT NULL,
        FechaCargaDw      DATETIME2(7)  NOT NULL CONSTRAINT DF_dw_factMeteoDaily_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId             INT           NULL,
        CONSTRAINT UQ_dw_factMeteoDaily_SiteFecha UNIQUE (Site, MeasuredDate)
    );
END
GO

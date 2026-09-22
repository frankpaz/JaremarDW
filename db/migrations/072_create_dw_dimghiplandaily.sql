-- 072: dw.dimGhiPlanDaily -- dimension Gold (SCD Tipo 1), a partir de
-- [int].dimGhiPlanDaily.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'dimGhiPlanDaily'
)
BEGIN
    CREATE TABLE dw.dimGhiPlanDaily (
        GhiPlanDailyKey   INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_dimGhiPlanDaily PRIMARY KEY,
        Site              NVARCHAR(40)  NOT NULL,
        DayOfYear         SMALLINT      NOT NULL,
        MonthOfYear       TINYINT       NOT NULL,
        DayOfMonth        TINYINT       NOT NULL,
        GhiP50WhM2        DECIMAL(9,2)  NOT NULL,
        GhiP90WhM2        DECIMAL(9,2)  NOT NULL,
        GhiP10WhM2        DECIMAL(9,2)  NOT NULL,
        HsfP50Hrs         DECIMAL(5,2)  NOT NULL,
        WindSpeedP50Mps   DECIMAL(5,2)  NOT NULL,
        SampleCount       SMALLINT      NOT NULL,
        GsaVintage        NVARCHAR(100) NULL,
        SourceLoadedAt    DATETIME2(7)  NULL,
        EsVigente         BIT           NOT NULL CONSTRAINT DF_dw_dimGhiPlanDaily_EsVigente DEFAULT (1),
        HashDiff          BINARY(32)    NOT NULL,
        FechaCargaDw      DATETIME2(7)  NOT NULL CONSTRAINT DF_dw_dimGhiPlanDaily_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId             INT           NULL,
        CONSTRAINT UQ_dw_dimGhiPlanDaily_SiteDia UNIQUE (Site, DayOfYear)
    );
END
GO

-- 070: [int].dimGhiPlanDaily -- version Silver de stg.dimGhiPlanDaily
-- (dominio Solar). Llave de negocio compuesta (Site, DayOfYear) -- plan
-- diario de irradiancia (P10/P50/P90) por sitio, derivado del GSA. 9 sitios
-- x 365 dias = 3285 filas.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'dimGhiPlanDaily'
)
BEGIN
    CREATE TABLE [int].dimGhiPlanDaily (
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
        EsVigente         BIT           NOT NULL CONSTRAINT DF_Int_dimGhiPlanDaily_EsVigente DEFAULT (1),
        HashDiff          BINARY(32)    NOT NULL,
        FechaCargaInt     DATETIME2(7)  NOT NULL CONSTRAINT DF_Int_dimGhiPlanDaily_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId             INT           NULL,
        CONSTRAINT PK_Int_dimGhiPlanDaily PRIMARY KEY (Site, DayOfYear)
    );
END
GO

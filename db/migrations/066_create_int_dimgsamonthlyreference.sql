-- 066: [int].dimGsaMonthlyReference -- version Silver de
-- stg.dimGsaMonthlyReference (dominio Solar). Llave de negocio compuesta
-- (Site, MonthOfYear) -- referencia mensual de irradiancia del Global Solar
-- Atlas por sitio, sin ID unico propio. 9 sitios x 12 meses = 108 filas.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'dimGsaMonthlyReference'
)
BEGIN
    CREATE TABLE [int].dimGsaMonthlyReference (
        Site            NVARCHAR(40)  NOT NULL,
        MonthOfYear     TINYINT       NOT NULL,
        GhiKwhM2Day     DECIMAL(5,2)  NOT NULL,
        DifKwhM2Day     DECIMAL(5,2)  NULL,
        DniKwhM2Day     DECIMAL(5,2)  NULL,
        SiteName        NVARCHAR(400) NULL,
        Lat             DECIMAL(9,6)  NOT NULL,
        Lon             DECIMAL(9,6)  NOT NULL,
        Units           NVARCHAR(40)  NOT NULL,
        Source          NVARCHAR(200) NULL,
        Dataset         NVARCHAR(200) NULL,
        Segment         NVARCHAR(200) NULL,
        Vintage         NVARCHAR(100) NULL,
        ExtractedAt     DATE          NULL,
        ExtractedBy     NVARCHAR(200) NULL,
        GhiAnnualWeb    DECIMAL(8,2)  NULL,
        SourceLoadedAt  DATETIME2(7)  NULL,
        EsVigente       BIT           NOT NULL CONSTRAINT DF_Int_dimGsaMonthlyReference_EsVigente DEFAULT (1),
        HashDiff        BINARY(32)    NOT NULL,
        FechaCargaInt   DATETIME2(7)  NOT NULL CONSTRAINT DF_Int_dimGsaMonthlyReference_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId           INT           NULL,
        CONSTRAINT PK_Int_dimGsaMonthlyReference PRIMARY KEY (Site, MonthOfYear)
    );
END
GO

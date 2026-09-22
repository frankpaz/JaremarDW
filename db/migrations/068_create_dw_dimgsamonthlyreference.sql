-- 068: dw.dimGsaMonthlyReference -- dimension Gold (SCD Tipo 1), a partir de
-- [int].dimGsaMonthlyReference.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'dimGsaMonthlyReference'
)
BEGIN
    CREATE TABLE dw.dimGsaMonthlyReference (
        GsaMonthlyReferenceKey  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_dimGsaMonthlyReference PRIMARY KEY,
        Site                    NVARCHAR(40)  NOT NULL,
        MonthOfYear              TINYINT       NOT NULL,
        GhiKwhM2Day              DECIMAL(5,2)  NOT NULL,
        DifKwhM2Day              DECIMAL(5,2)  NULL,
        DniKwhM2Day              DECIMAL(5,2)  NULL,
        SiteName                 NVARCHAR(400) NULL,
        Lat                      DECIMAL(9,6)  NOT NULL,
        Lon                      DECIMAL(9,6)  NOT NULL,
        Units                    NVARCHAR(40)  NOT NULL,
        Source                   NVARCHAR(200) NULL,
        Dataset                  NVARCHAR(200) NULL,
        Segment                  NVARCHAR(200) NULL,
        Vintage                  NVARCHAR(100) NULL,
        ExtractedAt              DATE          NULL,
        ExtractedBy              NVARCHAR(200) NULL,
        GhiAnnualWeb             DECIMAL(8,2)  NULL,
        SourceLoadedAt           DATETIME2(7)  NULL,
        EsVigente                BIT           NOT NULL CONSTRAINT DF_dw_dimGsaMonthlyReference_EsVigente DEFAULT (1),
        HashDiff                 BINARY(32)    NOT NULL,
        FechaCargaDw             DATETIME2(7)  NOT NULL CONSTRAINT DF_dw_dimGsaMonthlyReference_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId                    INT           NULL,
        CONSTRAINT UQ_dw_dimGsaMonthlyReference_SiteMes UNIQUE (Site, MonthOfYear)
    );
END
GO

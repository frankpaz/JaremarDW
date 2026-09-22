-- 092: [int].factMeteoDaily -- version Silver de stg.factMeteoDaily (dominio
-- Solar). A diferencia de los demas facts Solar (entidades ABP con Id/
-- IsDeleted/CreationTime), este no trae ese audit trail -- mismo estilo que
-- las dims meteo (dimGhiPlanDaily/dimGsaMonthlyReference): llave de negocio
-- compuesta (Site, MeasuredDate), curado manualmente (fuente NASA POWER),
-- crece un dia por sitio por corrida. Por eso se trata con el patron FULL +
-- SCD Tipo 1 (EsVigente/HashDiff) de las dimensiones, no con el patron
-- incremental por watermark de los facts ABP.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'factMeteoDaily'
)
BEGIN
    CREATE TABLE [int].factMeteoDaily (
        Site              NVARCHAR(40)  NOT NULL,
        MeasuredDate      DATE          NOT NULL,
        GhiRealWhM2       DECIMAL(9,2)  NULL,
        HsfRealHrs        DECIMAL(5,2)  NULL,
        WindSpeedRealMps  DECIMAL(5,2)  NULL,
        Source            NVARCHAR(100) NOT NULL,
        SourceVersion     NVARCHAR(100) NULL,
        RetrievedAt       DATETIME2(7)  NOT NULL,
        SourceLoadedAt    DATETIME2(7)  NULL,
        EsVigente         BIT           NOT NULL CONSTRAINT DF_Int_factMeteoDaily_EsVigente DEFAULT (1),
        HashDiff          BINARY(32)    NOT NULL,
        FechaCargaInt     DATETIME2(7)  NOT NULL CONSTRAINT DF_Int_factMeteoDaily_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId             INT           NULL,
        CONSTRAINT PK_Int_factMeteoDaily PRIMARY KEY (Site, MeasuredDate)
    );
END
GO

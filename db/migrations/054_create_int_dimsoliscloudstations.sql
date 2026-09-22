-- 054: [int].dimSoliscloudStations -- version Silver de stg.dimSoliscloudStations
-- (dominio Solar). Llave de negocio StationId (nvarchar, unico y sin nulos
-- en la practica). CreateDate llega como epoch en milisegundos -- se tipa a
-- DATETIME2.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'dimSoliscloudStations'
)
BEGIN
    CREATE TABLE [int].dimSoliscloudStations (
        StationId       NVARCHAR(200) NOT NULL CONSTRAINT PK_Int_dimSoliscloudStations PRIMARY KEY,
        StationName     NVARCHAR(900) NULL,
        Addr            NVARCHAR(900) NULL,
        Country         NVARCHAR(400) NULL,
        TimeZone        DECIMAL(5,2)  NULL,
        CreateDate      DATETIME2(3)  NULL,
        EsVigente       BIT           NOT NULL CONSTRAINT DF_Int_dimSoliscloudStations_EsVigente DEFAULT (1),
        HashDiff        BINARY(32)    NOT NULL,
        FechaCargaInt   DATETIME2(7)  NOT NULL CONSTRAINT DF_Int_dimSoliscloudStations_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId           INT           NULL
    );
END
GO

-- 056: dw.dimSoliscloudStations -- dimension Gold (SCD Tipo 1), a partir de [int].dimSoliscloudStations.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'dimSoliscloudStations'
)
BEGIN
    CREATE TABLE dw.dimSoliscloudStations (
        SoliscloudStationKey  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_dimSoliscloudStations PRIMARY KEY,
        StationId             NVARCHAR(200) NOT NULL,
        StationName           NVARCHAR(900) NULL,
        Addr                  NVARCHAR(900) NULL,
        Country               NVARCHAR(400) NULL,
        TimeZone              DECIMAL(5,2)  NULL,
        CreateDate            DATETIME2(3)  NULL,
        EsVigente             BIT           NOT NULL CONSTRAINT DF_dw_dimSoliscloudStations_EsVigente DEFAULT (1),
        HashDiff              BINARY(32)    NOT NULL,
        FechaCargaDw          DATETIME2(7)  NOT NULL CONSTRAINT DF_dw_dimSoliscloudStations_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId                 INT           NULL,
        CONSTRAINT UQ_dw_dimSoliscloudStations_StationId UNIQUE (StationId)
    );
END
GO

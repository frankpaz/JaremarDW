-- 048: dw.dimHuaweiStations -- dimension Gold (SCD Tipo 1), a partir de [int].dimHuaweiStations.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'dimHuaweiStations'
)
BEGIN
    CREATE TABLE dw.dimHuaweiStations (
        HuaweiStationKey    INT IDENTITY(1,1)    NOT NULL CONSTRAINT PK_dw_dimHuaweiStations PRIMARY KEY,
        StationCode         NVARCHAR(200)         NOT NULL,
        StationName         NVARCHAR(500)         NULL,
        StationAddress      NVARCHAR(1000)        NULL,
        Longitude           FLOAT                 NULL,
        Latitude            FLOAT                 NULL,
        Capacity            DECIMAL(18,2)         NULL,
        ContactPerson       NVARCHAR(500)         NULL,
        ContactMethod       NVARCHAR(500)         NULL,
        GridConnectionDate  DATETIMEOFFSET(7)     NULL,
        EsVigente           BIT                   NOT NULL CONSTRAINT DF_dw_dimHuaweiStations_EsVigente DEFAULT (1),
        HashDiff            BINARY(32)            NOT NULL,
        FechaCargaDw        DATETIME2(7)          NOT NULL CONSTRAINT DF_dw_dimHuaweiStations_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId               INT                   NULL,
        CONSTRAINT UQ_dw_dimHuaweiStations_StationCode UNIQUE (StationCode)
    );
END
GO

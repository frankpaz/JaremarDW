-- 046: [int].dimHuaweiStations -- version Silver de stg.dimHuaweiStations (dominio Solar).
-- Llave de negocio StationCode (nvarchar, unico y sin nulos en la practica).
-- GridConnectionDate llega como texto ISO8601 con offset (ej.
-- '2025-11-18T00:00:00-06:00') -- se tipa a DATETIMEOFFSET.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'dimHuaweiStations'
)
BEGIN
    CREATE TABLE [int].dimHuaweiStations (
        StationCode         NVARCHAR(200)         NOT NULL CONSTRAINT PK_Int_dimHuaweiStations PRIMARY KEY,
        StationName         NVARCHAR(500)         NULL,
        StationAddress      NVARCHAR(1000)        NULL,
        Longitude           FLOAT                 NULL,
        Latitude            FLOAT                 NULL,
        Capacity            DECIMAL(18,2)         NULL,
        ContactPerson       NVARCHAR(500)         NULL,
        ContactMethod       NVARCHAR(500)         NULL,
        GridConnectionDate  DATETIMEOFFSET(7)     NULL,
        EsVigente           BIT                   NOT NULL CONSTRAINT DF_Int_dimHuaweiStations_EsVigente DEFAULT (1),
        HashDiff            BINARY(32)            NOT NULL,
        FechaCargaInt       DATETIME2(7)          NOT NULL CONSTRAINT DF_Int_dimHuaweiStations_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId               INT                   NULL
    );
END
GO

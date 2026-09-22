-- 050: [int].dimHuaweiDevices -- version Silver de stg.dimHuaweiDevices (dominio Solar).
-- Llave de negocio DeviceId (nvarchar, unico y sin nulos en la practica).
-- StationCode se preserva como atributo/FK logica hacia dimHuaweiStations; el
-- join a la llave subrogada de dw.dimHuaweiStations ocurre en la capa Gold.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'dimHuaweiDevices'
)
BEGIN
    CREATE TABLE [int].dimHuaweiDevices (
        DeviceId          NVARCHAR(200) NOT NULL CONSTRAINT PK_Int_dimHuaweiDevices PRIMARY KEY,
        StationCode       NVARCHAR(200) NOT NULL,
        DeviceEsn         NVARCHAR(200) NULL,
        DeviceName        NVARCHAR(500) NULL,
        DeviceTypeId      INT           NULL,
        Model             NVARCHAR(300) NULL,
        SoftwareVersion   NVARCHAR(200) NULL,
        OptimizerNumber   INT           NULL,
        InvType           NVARCHAR(300) NULL,
        Longitude         FLOAT         NULL,
        Latitude          FLOAT         NULL,
        IsGenerator       BIT           NOT NULL,
        EsVigente         BIT           NOT NULL CONSTRAINT DF_Int_dimHuaweiDevices_EsVigente DEFAULT (1),
        HashDiff          BINARY(32)    NOT NULL,
        FechaCargaInt     DATETIME2(7)  NOT NULL CONSTRAINT DF_Int_dimHuaweiDevices_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId             INT           NULL
    );
END
GO

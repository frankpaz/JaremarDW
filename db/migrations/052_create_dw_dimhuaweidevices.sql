-- 052: dw.dimHuaweiDevices -- dimension Gold (SCD Tipo 1), a partir de [int].dimHuaweiDevices.
-- HuaweiStationKey referencia la llave subrogada de dw.dimHuaweiStations
-- (resuelta en el merge Gold por StationCode). DeviceId se conserva como
-- llave de negocio.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'dimHuaweiDevices'
)
BEGIN
    CREATE TABLE dw.dimHuaweiDevices (
        HuaweiDeviceKey    INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_dimHuaweiDevices PRIMARY KEY,
        HuaweiStationKey   INT           NOT NULL,
        StationCode        NVARCHAR(200) NOT NULL,
        DeviceId           NVARCHAR(200) NOT NULL,
        DeviceEsn          NVARCHAR(200) NULL,
        DeviceName         NVARCHAR(500) NULL,
        DeviceTypeId       INT           NULL,
        Model              NVARCHAR(300) NULL,
        SoftwareVersion    NVARCHAR(200) NULL,
        OptimizerNumber    INT           NULL,
        InvType            NVARCHAR(300) NULL,
        Longitude          FLOAT         NULL,
        Latitude           FLOAT         NULL,
        IsGenerator        BIT           NOT NULL,
        EsVigente          BIT           NOT NULL CONSTRAINT DF_dw_dimHuaweiDevices_EsVigente DEFAULT (1),
        HashDiff           BINARY(32)    NOT NULL,
        FechaCargaDw       DATETIME2(7)  NOT NULL CONSTRAINT DF_dw_dimHuaweiDevices_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId              INT           NULL,
        CONSTRAINT UQ_dw_dimHuaweiDevices_DeviceId UNIQUE (DeviceId),
        CONSTRAINT FK_dw_dimHuaweiDevices_dimHuaweiStations FOREIGN KEY (HuaweiStationKey) REFERENCES dw.dimHuaweiStations (HuaweiStationKey)
    );
END
GO

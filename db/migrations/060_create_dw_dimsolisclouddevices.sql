-- 060: dw.dimSoliscloudDevices -- dimension Gold (SCD Tipo 1), a partir de
-- [int].dimSoliscloudDevices. SoliscloudStationKey referencia la llave
-- subrogada de dw.dimSoliscloudStations (resuelta en el merge Gold por
-- StationId). DeviceId se conserva como llave de negocio.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'dimSoliscloudDevices'
)
BEGIN
    CREATE TABLE dw.dimSoliscloudDevices (
        SoliscloudDeviceKey      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_dimSoliscloudDevices PRIMARY KEY,
        SoliscloudStationKey     INT           NOT NULL,
        StationId                NVARCHAR(200) NOT NULL,
        DeviceId                 NVARCHAR(200) NOT NULL,
        DeviceSn                 NVARCHAR(400) NULL,
        Model                    NVARCHAR(400) NULL,
        ProductModel             NVARCHAR(400) NULL,
        CollectorSn              NVARCHAR(400) NULL,
        InverterSoftwareVersion  NVARCHAR(200) NULL,
        TimeZone                 DECIMAL(5,2)  NULL,
        IsGenerator              BIT           NOT NULL,
        EsVigente                BIT           NOT NULL CONSTRAINT DF_dw_dimSoliscloudDevices_EsVigente DEFAULT (1),
        HashDiff                 BINARY(32)    NOT NULL,
        FechaCargaDw             DATETIME2(7)  NOT NULL CONSTRAINT DF_dw_dimSoliscloudDevices_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId                    INT           NULL,
        CONSTRAINT UQ_dw_dimSoliscloudDevices_DeviceId UNIQUE (DeviceId),
        CONSTRAINT FK_dw_dimSoliscloudDevices_dimSoliscloudStations FOREIGN KEY (SoliscloudStationKey) REFERENCES dw.dimSoliscloudStations (SoliscloudStationKey)
    );
END
GO

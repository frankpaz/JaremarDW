-- 085: dw.factHuaweiEnergyAndPowerPv -- hecho Gold, a partir de
-- [int].factHuaweiEnergyAndPowerPv. HuaweiDeviceKey se resuelve por
-- DeviceId contra dw.dimHuaweiDevices en el merge Gold via LEFT JOIN (no
-- INNER/FK real, para tolerar filas nuevas de un dispositivo que aun no
-- este en la dimension por lag de carga).

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'factHuaweiEnergyAndPowerPv'
)
BEGIN
    CREATE TABLE dw.factHuaweiEnergyAndPowerPv (
        Id                     BIGINT         NOT NULL CONSTRAINT PK_dw_factHuaweiEnergyAndPowerPv PRIMARY KEY,
        HuaweiDeviceKey         INT            NULL,
        DeviceId                 NVARCHAR(200)  NOT NULL,
        Time                      DATETIME2(7)   NOT NULL,
        InstalledCapacity          DECIMAL(18,3)  NULL,
        PerpowerRatio               DECIMAL(18,4)  NULL,
        ProductPower                 DECIMAL(18,3)  NULL,
        CreationTime                  DATETIME2(7)   NOT NULL,
        LastModificationTime           DATETIME2(7)   NULL,
        IsDeleted                       BIT            NOT NULL,
        HashDiff                        BINARY(32)     NOT NULL,
        FechaCargaDw                     DATETIME2(7)   NOT NULL CONSTRAINT DF_dw_factHuaweiEnergyAndPowerPv_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId                            INT            NULL
    );
    CREATE INDEX IX_dw_factHuaweiEnergyAndPowerPv_HuaweiDeviceKey ON dw.factHuaweiEnergyAndPowerPv (HuaweiDeviceKey);
    CREATE INDEX IX_dw_factHuaweiEnergyAndPowerPv_Time ON dw.factHuaweiEnergyAndPowerPv (Time);
END
GO

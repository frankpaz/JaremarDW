-- 083: [int].factHuaweiEnergyAndPowerPv -- version Silver de
-- stg.factHuaweiEnergyAndPowerPv (dominio Solar). Entidad ABP con KPIs
-- diarios de Huawei en un campo JSON (KpiData) en vez de columnas planas
-- -- shape consistente confirmado en los 612 registros actuales: siempre
-- {"installed_capacity","perpower_ratio","product_power"}. Se parsean a
-- columnas tipadas para uso analitico y se conserva el JSON crudo
-- (KpiDataRaw) por si el origen agrega mas claves a futuro. Time llega
-- como epoch en milisegundos -- se tipa a DATETIME2. Carga INCREMENTAL por
-- watermark, igual que los facts SMA (comparacion truncada a milisegundo
-- desde el inicio).

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'factHuaweiEnergyAndPowerPv'
)
BEGIN
    CREATE TABLE [int].factHuaweiEnergyAndPowerPv (
        Id                     BIGINT         NOT NULL CONSTRAINT PK_Int_factHuaweiEnergyAndPowerPv PRIMARY KEY,
        DeviceId                NVARCHAR(200)  NOT NULL,
        Time                     DATETIME2(7)   NOT NULL,
        InstalledCapacity         DECIMAL(18,3)  NULL,
        PerpowerRatio              DECIMAL(18,4)  NULL,
        ProductPower                DECIMAL(18,3)  NULL,
        KpiDataRaw                   NVARCHAR(MAX)  NOT NULL,
        CreationTime                  DATETIME2(7)   NOT NULL,
        LastModificationTime           DATETIME2(7)   NULL,
        IsDeleted                       BIT            NOT NULL,
        HashDiff                        BINARY(32)     NOT NULL,
        FechaCargaInt                    DATETIME2(7)   NOT NULL CONSTRAINT DF_Int_factHuaweiEnergyAndPowerPv_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId                            INT            NULL
    );
    CREATE INDEX IX_Int_factHuaweiEnergyAndPowerPv_DeviceId ON [int].factHuaweiEnergyAndPowerPv (DeviceId);
    CREATE INDEX IX_Int_factHuaweiEnergyAndPowerPv_Time ON [int].factHuaweiEnergyAndPowerPv (Time);
END
GO

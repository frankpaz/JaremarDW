-- 098: dw.factGrowattEnergyAndPowerPv -- hecho Gold, a partir de
-- [int].factGrowattEnergyAndPowerPv. Sin llave subrogada de dispositivo: no
-- existe dimGrowattDevices en este dominio (a diferencia de SMA/Huawei/
-- Soliscloud) -- DeviceId queda como atributo plano.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'factGrowattEnergyAndPowerPv'
)
BEGIN
    CREATE TABLE dw.factGrowattEnergyAndPowerPv (
        Id                     BIGINT         NOT NULL CONSTRAINT PK_dw_factGrowattEnergyAndPowerPv PRIMARY KEY,
        DeviceId                NVARCHAR(200)  NOT NULL,
        Time                     DATETIME2(7)   NOT NULL,
        Status                   INT            NULL,
        StatusText               NVARCHAR(200)  NULL,
        PowerToday               DECIMAL(18,3)  NULL,
        PowerTotal               DECIMAL(18,3)  NULL,
        EacToday                 DECIMAL(18,3)  NULL,
        EacTotal                 DECIMAL(18,3)  NULL,
        Pac                      DECIMAL(18,2)  NULL,
        Ppv                      DECIMAL(18,2)  NULL,
        Pf                       DECIMAL(9,4)   NULL,
        Fac                      DECIMAL(9,3)   NULL,
        VacR                     DECIMAL(9,2)   NULL,
        VacS                     DECIMAL(9,2)   NULL,
        VacT                     DECIMAL(9,2)   NULL,
        IacR                     DECIMAL(9,2)   NULL,
        IacS                     DECIMAL(9,2)   NULL,
        IacT                     DECIMAL(9,2)   NULL,
        PacR                     DECIMAL(18,2)  NULL,
        PacS                     DECIMAL(18,2)  NULL,
        PacT                     DECIMAL(18,2)  NULL,
        Temperature1             DECIMAL(9,2)   NULL,
        Temperature2             DECIMAL(9,2)   NULL,
        Temperature3             DECIMAL(9,2)   NULL,
        WarnCode                 INT            NULL,
        FaultType                INT            NULL,
        FaultCode1               INT            NULL,
        FaultCode2               INT            NULL,
        PvIso                    DECIMAL(18,2)  NULL,
        Gfci                     DECIMAL(18,2)  NULL,
        CreationTime             DATETIME2(7)   NOT NULL,
        LastModificationTime     DATETIME2(7)   NULL,
        IsDeleted                BIT            NOT NULL,
        HashDiff                 BINARY(32)     NOT NULL,
        FechaCargaDw             DATETIME2(7)   NOT NULL CONSTRAINT DF_dw_factGrowattEnergyAndPowerPv_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId                    INT            NULL
    );
    CREATE INDEX IX_dw_factGrowattEnergyAndPowerPv_DeviceId ON dw.factGrowattEnergyAndPowerPv (DeviceId);
    CREATE INDEX IX_dw_factGrowattEnergyAndPowerPv_Time ON dw.factGrowattEnergyAndPowerPv (Time);
END
GO

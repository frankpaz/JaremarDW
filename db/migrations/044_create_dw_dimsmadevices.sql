-- 044: dw.dimSmaDevices -- dimension Gold (SCD Tipo 1), a partir de [int].dimSmaDevices.
-- SmaPlantaKey referencia la llave subrogada de dw.dimSmaPlants (resuelta en
-- el merge Gold por PlantId). DeviceId se conserva como llave de negocio.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'dimSmaDevices'
)
BEGIN
    CREATE TABLE dw.dimSmaDevices (
        SmaDeviceKey      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_dimSmaDevices PRIMARY KEY,
        SmaPlantaKey      INT           NOT NULL,
        PlantId           BIGINT        NOT NULL,
        DeviceId          BIGINT        NOT NULL,
        DeviceName        NVARCHAR(500) NULL,
        DeviceTimezone    NVARCHAR(200) NULL,
        DeviceType        NVARCHAR(200) NULL,
        Product           NVARCHAR(300) NULL,
        ProductId         BIGINT        NULL,
        Serial            NVARCHAR(200) NULL,
        Vendor            NVARCHAR(400) NULL,
        GeneratorPower    DECIMAL(18,2) NULL,
        GeneratorPowerDc  DECIMAL(18,2) NULL,
        IsActive          BIT           NULL,
        IsGenerator       BIT           NULL,
        EsVigente         BIT           NOT NULL CONSTRAINT DF_dw_dimSmaDevices_EsVigente DEFAULT (1),
        HashDiff          BINARY(32)    NOT NULL,
        FechaCargaDw      DATETIME2(7)  NOT NULL CONSTRAINT DF_dw_dimSmaDevices_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId             INT           NULL,
        CONSTRAINT UQ_dw_dimSmaDevices_DeviceId UNIQUE (DeviceId),
        CONSTRAINT FK_dw_dimSmaDevices_dimSmaPlants FOREIGN KEY (SmaPlantaKey) REFERENCES dw.dimSmaPlants (SmaPlantaKey)
    );
END
GO

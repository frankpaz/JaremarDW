-- 042: [int].dimSmaDevices -- version Silver de stg.dimSmaDevices (dominio Solar).
-- Llave de negocio DeviceId (bigint, unico y sin nulos en la practica).
-- PlantId se preserva como atributo/FK logica hacia dimSmaPlants; el join a
-- la llave subrogada de dw.dimSmaPlants ocurre en la capa Gold.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'dimSmaDevices'
)
BEGIN
    CREATE TABLE [int].dimSmaDevices (
        DeviceId          BIGINT        NOT NULL CONSTRAINT PK_Int_dimSmaDevices PRIMARY KEY,
        PlantId           BIGINT        NOT NULL,
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
        EsVigente         BIT           NOT NULL CONSTRAINT DF_Int_dimSmaDevices_EsVigente DEFAULT (1),
        HashDiff          BINARY(32)    NOT NULL,
        FechaCargaInt     DATETIME2(7)  NOT NULL CONSTRAINT DF_Int_dimSmaDevices_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId             INT           NULL
    );
END
GO

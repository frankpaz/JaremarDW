-- 076: dw.factSmaPowerPlanta -- hecho Gold, a partir de [int].factSmaPowerPlanta.
-- SmaPlantaKey/SmaDeviceKey se resuelven por PlantId/DeviceId contra
-- dw.dimSmaPlants/dw.dimSmaDevices en el merge Gold, pero se dejan NULL-ables
-- y SIN FK: PlantId/DeviceId pueden venir vacios segun el tipo de fila (esta
-- tabla es a nivel planta, DeviceId puede no aplicar) y stg esta vacia hoy,
-- asi que el patron real de estos campos no se pudo validar contra datos.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'factSmaPowerPlanta'
)
BEGIN
    CREATE TABLE dw.factSmaPowerPlanta (
        Id                     BIGINT         NOT NULL CONSTRAINT PK_dw_factSmaPowerPlanta PRIMARY KEY,
        SmaPlantaKey            INT            NULL,
        SmaDeviceKey             INT            NULL,
        PlantId                  NVARCHAR(MAX)  NULL,
        DeviceId                 NVARCHAR(900)  NULL,
        SetType                  NVARCHAR(MAX)  NULL,
        Resolution                NVARCHAR(100)  NOT NULL,
        UnidadDeMedida             NVARCHAR(20)   NOT NULL,
        Time                       DATETIME2(7)   NOT NULL,
        PvGeneration               DECIMAL(18,2)  NOT NULL,
        CreationTime                DATETIME2(7)   NOT NULL,
        LastModificationTime         DATETIME2(7)   NULL,
        IsDeleted                    BIT            NOT NULL,
        HashDiff                     BINARY(32)     NOT NULL,
        FechaCargaDw                 DATETIME2(7)   NOT NULL CONSTRAINT DF_dw_factSmaPowerPlanta_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId                        INT            NULL
    );
    CREATE INDEX IX_dw_factSmaPowerPlanta_SmaPlantaKey ON dw.factSmaPowerPlanta (SmaPlantaKey);
    CREATE INDEX IX_dw_factSmaPowerPlanta_SmaDeviceKey ON dw.factSmaPowerPlanta (SmaDeviceKey);
    CREATE INDEX IX_dw_factSmaPowerPlanta_Time ON dw.factSmaPowerPlanta (Time);
END
GO

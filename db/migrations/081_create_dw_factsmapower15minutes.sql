-- 081: dw.factSmaPower15Minutes -- hecho Gold, a partir de
-- [int].factSmaPower15Minutes. SmaPlantaKey/SmaDeviceKey se resuelven por
-- PlantId/DeviceId contra dw.dimSmaPlants/dw.dimSmaDevices en el merge
-- Gold; NULL-ables y SIN FK (mismo motivo que factSmaPowerPlanta: stg vacia
-- hoy, PlantId/DeviceId pueden no aplicar segun el tipo de fila).

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'factSmaPower15Minutes'
)
BEGIN
    CREATE TABLE dw.factSmaPower15Minutes (
        Id                     BIGINT         NOT NULL CONSTRAINT PK_dw_factSmaPower15Minutes PRIMARY KEY,
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
        FechaCargaDw                 DATETIME2(7)   NOT NULL CONSTRAINT DF_dw_factSmaPower15Minutes_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId                        INT            NULL
    );
    CREATE INDEX IX_dw_factSmaPower15Minutes_SmaPlantaKey ON dw.factSmaPower15Minutes (SmaPlantaKey);
    CREATE INDEX IX_dw_factSmaPower15Minutes_SmaDeviceKey ON dw.factSmaPower15Minutes (SmaDeviceKey);
    CREATE INDEX IX_dw_factSmaPower15Minutes_Time ON dw.factSmaPower15Minutes (Time);
END
GO

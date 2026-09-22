-- 062: [int].dimDeviceCapacity -- version Silver de stg.dimDeviceCapacity
-- (dominio Solar). Llave de negocio InverterId (nvarchar, unico y sin nulos
-- en la practica). Catalogo curado manualmente (no viene de una API de
-- vendor) que documenta la capacidad nameplate por inversor en los 4
-- vendors (growatt/huawei/sma/soliscloud); JoinKeyKind + JoinKey son pistas
-- de como enlazarlo al dimXxxDevices correspondiente -- no es un FK
-- confiable (varia por vendor: device_sn, device_name, none), por eso no se
-- modela como relacion en Gold. LoadedAt del origen se renombra a
-- SourceLoadedAt para no confundirse con FechaCargaInt (nuestro propio
-- audit trail).

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'dimDeviceCapacity'
)
BEGIN
    CREATE TABLE [int].dimDeviceCapacity (
        InverterId       NVARCHAR(100) NOT NULL CONSTRAINT PK_Int_dimDeviceCapacity PRIMARY KEY,
        Vendor           NVARCHAR(40)  NOT NULL,
        PlantLabel       NVARCHAR(100) NOT NULL,
        ModelName        NVARCHAR(200) NOT NULL,
        JoinKeyKind      NVARCHAR(40)  NOT NULL,
        JoinKey          NVARCHAR(900) NULL,
        SourceSn         NVARCHAR(900) NULL,
        CapacityDcKwp    DECIMAL(9,3)  NOT NULL,
        CapacityAcKw     DECIMAL(9,2)  NOT NULL,
        IsPlaceholder    BIT           NOT NULL,
        SourceNote       NVARCHAR(800) NULL,
        Source           NVARCHAR(200) NULL,
        ExtractedAt      DATE          NULL,
        ExtractedBy      NVARCHAR(200) NULL,
        SourceLoadedAt   DATETIME2(7)  NULL,
        EsVigente        BIT           NOT NULL CONSTRAINT DF_Int_dimDeviceCapacity_EsVigente DEFAULT (1),
        HashDiff         BINARY(32)    NOT NULL,
        FechaCargaInt    DATETIME2(7)  NOT NULL CONSTRAINT DF_Int_dimDeviceCapacity_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId            INT           NULL
    );
END
GO

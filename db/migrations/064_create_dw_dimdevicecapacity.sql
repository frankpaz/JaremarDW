-- 064: dw.dimDeviceCapacity -- dimension Gold (SCD Tipo 1), a partir de
-- [int].dimDeviceCapacity. Sin FK a otras dimensiones dw: JoinKeyKind/JoinKey
-- son pistas de enlace que varian por vendor, no una relacion confiable.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'dimDeviceCapacity'
)
BEGIN
    CREATE TABLE dw.dimDeviceCapacity (
        DeviceCapacityKey  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_dimDeviceCapacity PRIMARY KEY,
        InverterId         NVARCHAR(100) NOT NULL,
        Vendor             NVARCHAR(40)  NOT NULL,
        PlantLabel         NVARCHAR(100) NOT NULL,
        ModelName          NVARCHAR(200) NOT NULL,
        JoinKeyKind        NVARCHAR(40)  NOT NULL,
        JoinKey            NVARCHAR(900) NULL,
        SourceSn           NVARCHAR(900) NULL,
        CapacityDcKwp      DECIMAL(9,3)  NOT NULL,
        CapacityAcKw       DECIMAL(9,2)  NOT NULL,
        IsPlaceholder      BIT           NOT NULL,
        SourceNote         NVARCHAR(800) NULL,
        Source             NVARCHAR(200) NULL,
        ExtractedAt        DATE          NULL,
        ExtractedBy        NVARCHAR(200) NULL,
        SourceLoadedAt     DATETIME2(7)  NULL,
        EsVigente          BIT           NOT NULL CONSTRAINT DF_dw_dimDeviceCapacity_EsVigente DEFAULT (1),
        HashDiff           BINARY(32)    NOT NULL,
        FechaCargaDw       DATETIME2(7)  NOT NULL CONSTRAINT DF_dw_dimDeviceCapacity_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId              INT           NULL,
        CONSTRAINT UQ_dw_dimDeviceCapacity_InverterId UNIQUE (InverterId)
    );
END
GO

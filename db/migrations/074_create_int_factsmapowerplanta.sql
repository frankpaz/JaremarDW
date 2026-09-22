-- 074: [int].factSmaPowerPlanta -- version Silver de stg.factSmaPowerPlanta
-- (dominio Solar). Entidad tipo ABP (Id bigint ya es unico por diseno,
-- IsDeleted/CreatorUserId/etc. son el audit trail del origen). stg esta
-- vacia hoy (0 filas) -- el DDL se basa en la metadata real de columnas
-- (sys.columns), no en datos de muestra.
-- Carga INCREMENTAL (no FULL como las dimensiones): es una serie de tiempo
-- que puede crecer mucho, el merge Silver solo procesa filas con
-- CreationTime/LastModificationTime posteriores al ultimo watermark.
-- PlantId/SetType se preservan como NVARCHAR(MAX) igual que el origen (sin
-- MaxLength explicito en el origen ABP/EF Core).

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'factSmaPowerPlanta'
)
BEGIN
    CREATE TABLE [int].factSmaPowerPlanta (
        Id                     BIGINT         NOT NULL CONSTRAINT PK_Int_factSmaPowerPlanta PRIMARY KEY,
        PlantId                NVARCHAR(MAX)  NULL,
        DeviceId                NVARCHAR(900)  NULL,
        SetType                 NVARCHAR(MAX)  NULL,
        Resolution               NVARCHAR(100)  NOT NULL,
        UnidadDeMedida           NVARCHAR(20)   NOT NULL,
        Time                     DATETIME2(7)   NOT NULL,
        PvGeneration             DECIMAL(18,2)  NOT NULL,
        CreatorUserId            BIGINT         NULL,
        CreationTime             DATETIME2(7)   NOT NULL,
        LastModifierUserId       BIGINT         NULL,
        LastModificationTime     DATETIME2(7)   NULL,
        DeleterUserId            BIGINT         NULL,
        DeletionTime             DATETIME2(7)   NULL,
        IsDeleted                BIT            NOT NULL,
        HashDiff                 BINARY(32)     NOT NULL,
        FechaCargaInt            DATETIME2(7)   NOT NULL CONSTRAINT DF_Int_factSmaPowerPlanta_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId                    INT            NULL
    );
    CREATE INDEX IX_Int_factSmaPowerPlanta_DeviceId ON [int].factSmaPowerPlanta (DeviceId);
    CREATE INDEX IX_Int_factSmaPowerPlanta_Time ON [int].factSmaPowerPlanta (Time);
END
GO

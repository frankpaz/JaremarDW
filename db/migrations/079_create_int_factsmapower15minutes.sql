-- 079: [int].factSmaPower15Minutes -- version Silver de
-- stg.factSmaPower15Minutes (dominio Solar). Mismo shape que
-- factSmaPowerPlanta (entidad ABP), pero a resolucion de 15 minutos en vez
-- de nivel planta. stg vacia hoy (0 filas) -- DDL basado en metadata real
-- de columnas (sys.columns). Carga INCREMENTAL por watermark
-- (CreationTime/LastModificationTime), igual que factSmaPowerPlanta.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'factSmaPower15Minutes'
)
BEGIN
    CREATE TABLE [int].factSmaPower15Minutes (
        Id                     BIGINT         NOT NULL CONSTRAINT PK_Int_factSmaPower15Minutes PRIMARY KEY,
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
        FechaCargaInt            DATETIME2(7)   NOT NULL CONSTRAINT DF_Int_factSmaPower15Minutes_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId                    INT            NULL
    );
    CREATE INDEX IX_Int_factSmaPower15Minutes_DeviceId ON [int].factSmaPower15Minutes (DeviceId);
    CREATE INDEX IX_Int_factSmaPower15Minutes_Time ON [int].factSmaPower15Minutes (Time);
END
GO

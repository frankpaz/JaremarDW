-- 038: [int].dimSmaPlants -- version Silver de stg.dimSmaPlants (dominio Solar).
-- stg.dimSmaPlants es un snapshot externo (API SMA), sin columnas de
-- auditoria propias (no LoadedAt) y sin duplicados de PlantId en la practica;
-- se mantiene el dedup defensivo por consistencia con el resto del framework.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'dimSmaPlants'
)
BEGIN
    CREATE TABLE [int].dimSmaPlants (
        PlantId         INT           NOT NULL CONSTRAINT PK_Int_dimSmaPlants PRIMARY KEY,
        PlantName       NVARCHAR(500) NOT NULL,
        PlantTimezone   NVARCHAR(200) NOT NULL,
        EsVigente       BIT           NOT NULL CONSTRAINT DF_Int_dimSmaPlants_EsVigente DEFAULT (1),
        HashDiff        BINARY(32)    NOT NULL,
        FechaCargaInt   DATETIME2(7)  NOT NULL CONSTRAINT DF_Int_dimSmaPlants_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId           INT           NULL
    );
END
GO

-- 040: dw.dimSmaPlants -- dimension Gold (SCD Tipo 1), a partir de [int].dimSmaPlants.
-- Nombres de columna del vendor (SMA) se preservan tal cual -- ya son
-- legibles en ingles, distinto al caso AS400 (codigos crypticos SVSGVL/etc.).

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'dimSmaPlants'
)
BEGIN
    CREATE TABLE dw.dimSmaPlants (
        SmaPlantaKey    INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_dimSmaPlants PRIMARY KEY,
        PlantId         INT           NOT NULL,
        PlantName       NVARCHAR(500) NOT NULL,
        PlantTimezone   NVARCHAR(200) NOT NULL,
        EsVigente       BIT           NOT NULL CONSTRAINT DF_dw_dimSmaPlants_EsVigente DEFAULT (1),
        HashDiff        BINARY(32)    NOT NULL,
        FechaCargaDw    DATETIME2(7)  NOT NULL CONSTRAINT DF_dw_dimSmaPlants_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId           INT           NULL,
        CONSTRAINT UQ_dw_dimSmaPlants_PlantId UNIQUE (PlantId)
    );
END
GO

-- 023: [int].dimCentroCosto -- version Silver de stg.dimCentroCosto.
-- Mismo patron que dimEmpresas/dimSector: llave de negocio SVSGVL, SVID sin
-- significado confirmado (se trae como atributo), SVDATE/SVTIME convertidos
-- a DATE/TIME reales.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'dimCentroCosto'
)
BEGIN
    CREATE TABLE [int].dimCentroCosto (
        SVSGVL          NVARCHAR(16)  NOT NULL CONSTRAINT PK_Int_dimCentroCosto PRIMARY KEY,
        SVID            NVARCHAR(2)   NULL,
        SVLDES          NVARCHAR(30)  NULL,
        SVDATE          DATE          NULL,
        SVTIME          TIME(0)       NULL,
        EsVigente       BIT           NOT NULL CONSTRAINT DF_Int_dimCentroCosto_EsVigente DEFAULT (1),
        HashDiff        BINARY(32)    NOT NULL,
        FechaCargaInt   DATETIME2(7)  NOT NULL CONSTRAINT DF_Int_dimCentroCosto_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId           INT           NULL
    );
END
GO

-- 019: [int].dimSector -- version Silver de stg.dimSector.
-- Mismo patron que dimEmpresas: llave de negocio SVSGVL, SVID sin
-- significado confirmado (se trae como atributo), SVDATE/SVTIME
-- convertidos a DATE/TIME reales.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'dimSector'
)
BEGIN
    CREATE TABLE [int].dimSector (
        SVSGVL          NVARCHAR(16)  NOT NULL CONSTRAINT PK_Int_dimSector PRIMARY KEY,
        SVID            NVARCHAR(2)   NULL,
        SVLDES          NVARCHAR(30)  NULL,
        SVDATE          DATE          NULL,
        SVTIME          TIME(0)       NULL,
        EsVigente       BIT           NOT NULL CONSTRAINT DF_Int_dimSector_EsVigente DEFAULT (1),
        HashDiff        BINARY(32)    NOT NULL,
        FechaCargaInt   DATETIME2(7)  NOT NULL CONSTRAINT DF_Int_dimSector_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId           INT           NULL
    );
END
GO

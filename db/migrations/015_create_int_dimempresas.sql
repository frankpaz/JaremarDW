-- 015: [int].dimEmpresas -- version Silver de stg.dimEmpresas.
-- Llave de negocio real: SVSGVL (unica en las 64 filas del origen, a
-- diferencia de SVID que solo tiene 2 valores -- SV/SZ, sin significado
-- confirmado, se trae como atributo). Convierte SVDATE/SVTIME (decimales
-- AAAAMMDD/HHMMSS) a DATE/TIME reales.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'dimEmpresas'
)
BEGIN
    CREATE TABLE [int].dimEmpresas (
        SVSGVL          NVARCHAR(16)  NOT NULL CONSTRAINT PK_Int_dimEmpresas PRIMARY KEY,
        SVID            NVARCHAR(2)   NULL,
        SVLDES          NVARCHAR(30)  NULL,
        SVDATE          DATE          NULL,
        SVTIME          TIME(0)       NULL,
        EsVigente       BIT           NOT NULL CONSTRAINT DF_Int_dimEmpresas_EsVigente DEFAULT (1),
        HashDiff        BINARY(32)    NOT NULL,
        FechaCargaInt   DATETIME2(7)  NOT NULL CONSTRAINT DF_Int_dimEmpresas_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId           INT           NULL
    );
END
GO

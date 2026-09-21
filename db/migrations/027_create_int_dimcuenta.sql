-- 027: [int].dimCuenta -- version Silver de stg.dimCuenta.
-- Mismo patron que dimEmpresas/dimSector/dimCentroCosto: llave de negocio
-- SVSGVL, SVID sin significado confirmado, SVDATE/SVTIME convertidos a
-- DATE/TIME reales.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'dimCuenta'
)
BEGIN
    CREATE TABLE [int].dimCuenta (
        SVSGVL          NVARCHAR(16)  NOT NULL CONSTRAINT PK_Int_dimCuenta PRIMARY KEY,
        SVID            NVARCHAR(2)   NULL,
        SVLDES          NVARCHAR(30)  NULL,
        SVDATE          DATE          NULL,
        SVTIME          TIME(0)       NULL,
        EsVigente       BIT           NOT NULL CONSTRAINT DF_Int_dimCuenta_EsVigente DEFAULT (1),
        HashDiff        BINARY(32)    NOT NULL,
        FechaCargaInt   DATETIME2(7)  NOT NULL CONSTRAINT DF_Int_dimCuenta_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId           INT           NULL
    );
END
GO

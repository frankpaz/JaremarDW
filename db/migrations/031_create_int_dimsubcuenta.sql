-- 031: [int].dimSubCuenta -- version Silver de stg.dimSubCuenta.
-- Mismo patron que dimCuenta/dimEmpresas/dimSector/dimCentroCosto.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'dimSubCuenta'
)
BEGIN
    CREATE TABLE [int].dimSubCuenta (
        SVSGVL          NVARCHAR(16)  NOT NULL CONSTRAINT PK_Int_dimSubCuenta PRIMARY KEY,
        SVID            NVARCHAR(2)   NULL,
        SVLDES          NVARCHAR(30)  NULL,
        SVDATE          DATE          NULL,
        SVTIME          TIME(0)       NULL,
        EsVigente       BIT           NOT NULL CONSTRAINT DF_Int_dimSubCuenta_EsVigente DEFAULT (1),
        HashDiff        BINARY(32)    NOT NULL,
        FechaCargaInt   DATETIME2(7)  NOT NULL CONSTRAINT DF_Int_dimSubCuenta_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId           INT           NULL
    );
END
GO

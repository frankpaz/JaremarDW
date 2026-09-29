-- 199: [int].dimProductoBascula -- version Silver de stg.dimProductoBascula (PROLXUSRF.BASPRODU, productos propios de la bascula, distintos del maestro del ERP).
-- Llave de negocio NUMPROD (441 productos al 2026-09-29).

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'dimProductoBascula'
)
BEGIN
    CREATE TABLE [int].dimProductoBascula (
        NUMPROD         INT           NOT NULL CONSTRAINT PK_Int_dimProductoBascula PRIMARY KEY,
        MOMPROD         NVARCHAR(40)  NULL,
        EsVigente       BIT           NOT NULL CONSTRAINT DF_Int_dimProductoBascula_EsVigente DEFAULT (1),
        HashDiff        BINARY(32)    NOT NULL,
        FechaCargaInt   DATETIME2(7)  NOT NULL CONSTRAINT DF_Int_dimProductoBascula_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId           INT           NULL
    );
END
GO

-- 013: dw.dimClasesProducto -- dimension Gold (SCD Tipo 1), a partir de
-- [int].dimClasesProducto. Nombres de negocio, mismo criterio que dw.dimProducto.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'dimClasesProducto'
)
BEGIN
    CREATE TABLE dw.dimClasesProducto (
        ClaseProductoKey    INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_dimClasesProducto PRIMARY KEY,
        CodigoClase          NVARCHAR(4)   NOT NULL,
        DescripcionClase     NVARCHAR(30)  NULL,
        EsVigente            BIT           NOT NULL CONSTRAINT DF_dw_dimClasesProducto_EsVigente DEFAULT (1),
        HashDiff             BINARY(32)    NOT NULL,
        FechaCargaDw         DATETIME2(7)  NOT NULL CONSTRAINT DF_dw_dimClasesProducto_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId                INT           NULL,
        CONSTRAINT UQ_dw_dimClasesProducto_CodigoClase UNIQUE (CodigoClase)
    );
END
GO

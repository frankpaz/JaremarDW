-- 201: dw.dimProductoBascula -- dimension Gold (SCD Tipo 1), a partir de [int].dimProductoBascula.
-- La usa dw.factBasculaBufalo (ProductoBasculaKey, via NUMPROD).

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'dimProductoBascula'
)
BEGIN
    CREATE TABLE dw.dimProductoBascula (
        ProductoBasculaKey           INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_dimProductoBascula PRIMARY KEY,
        CodigoProductoBascula        INT           NOT NULL,
        DescripcionProductoBascula   NVARCHAR(40)  NULL,
        EsVigente                    BIT           NOT NULL CONSTRAINT DF_dw_dimProductoBascula_EsVigente DEFAULT (1),
        HashDiff                     BINARY(32)    NOT NULL,
        FechaCargaDw                 DATETIME2(7)  NOT NULL CONSTRAINT DF_dw_dimProductoBascula_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId                        INT           NULL,
        CONSTRAINT UQ_dw_dimProductoBascula_Codigo UNIQUE (CodigoProductoBascula)
    );
END
GO

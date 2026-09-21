-- 011: [int].dimClasesProducto -- version Silver de stg.dimClasesProducto.
-- Tabla de referencia pequena (99 filas en origen), ICLAS ya es unico en AS400.
-- Se mantienen los codigos AS400 originales, igual que dimProducto en Silver.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'dimClasesProducto'
)
BEGIN
    CREATE TABLE [int].dimClasesProducto (
        ICLAS           NVARCHAR(4)   NOT NULL CONSTRAINT PK_Int_dimClasesProducto PRIMARY KEY,
        ICDES           NVARCHAR(30)  NULL,
        EsVigente       BIT           NOT NULL CONSTRAINT DF_Int_dimClasesProducto_EsVigente DEFAULT (1),
        HashDiff        BINARY(32)    NOT NULL,
        FechaCargaInt   DATETIME2(7)  NOT NULL CONSTRAINT DF_Int_dimClasesProducto_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId           INT           NULL
    );
END
GO

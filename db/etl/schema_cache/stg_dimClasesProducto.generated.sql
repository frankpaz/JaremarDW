IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'stg' AND t.name = 'dimClasesProducto'
)
BEGIN
    CREATE TABLE stg.dimClasesProducto (
    [ICLAS] NVARCHAR(2) NULL,
    [ICDES] NVARCHAR(30) NULL,
    [FechaCargaStg] DATETIME2(7) NOT NULL CONSTRAINT DF_dimClasesProducto_FechaCargaStg DEFAULT (SYSDATETIME()),
    [RunId] INT NULL
    );
END

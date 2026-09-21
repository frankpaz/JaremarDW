IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'stg' AND t.name = 'dimEmpresaMoneda'
)
BEGIN
    CREATE TABLE stg.dimEmpresaMoneda (
    [CMPNY] DECIMAL(2,0) NULL,
    [CCURCY] NVARCHAR(3) NULL,
    [FechaCargaStg] DATETIME2(7) NOT NULL CONSTRAINT DF_dimEmpresaMoneda_FechaCargaStg DEFAULT (SYSDATETIME()),
    [RunId] INT NULL
    );
END

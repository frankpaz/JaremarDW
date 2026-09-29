IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'stg' AND t.name = 'dimProductoBascula'
)
BEGIN
    CREATE TABLE stg.dimProductoBascula (
    [NUMPROD] DECIMAL(5,0) NULL,
    [MOMPROD] NVARCHAR(40) NULL,
    [FechaCargaStg] DATETIME2(7) NOT NULL CONSTRAINT DF_dimProductoBascula_FechaCargaStg DEFAULT (SYSDATETIME()),
    [RunId] INT NULL
    );
END

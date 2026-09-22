IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'stg' AND t.name = 'dimTerminosCompra'
)
BEGIN
    CREATE TABLE stg.dimTerminosCompra (
    [VTERM] NVARCHAR(2) NULL,
    [VTMDSC] NVARCHAR(15) NULL,
    [VTMDDY] DECIMAL(3,0) NULL,
    [VTTAXD] NVARCHAR(1) NULL,
    [FechaCargaStg] DATETIME2(7) NOT NULL CONSTRAINT DF_dimTerminosCompra_FechaCargaStg DEFAULT (SYSDATETIME()),
    [RunId] INT NULL
    );
END

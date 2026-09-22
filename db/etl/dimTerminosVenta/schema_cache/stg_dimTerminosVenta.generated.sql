IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'stg' AND t.name = 'dimTerminosVenta'
)
BEGIN
    CREATE TABLE stg.dimTerminosVenta (
    [TMCMPN] DECIMAL(2,0) NULL,
    [TMTERM] NVARCHAR(2) NULL,
    [TMDESC] NVARCHAR(15) NULL,
    [TMDUE] DECIMAL(5,0) NULL,
    [TMTAXD] NVARCHAR(1) NULL,
    [TMBBTA] NVARCHAR(1) NULL,
    [TMCWO] NVARCHAR(1) NULL,
    [FechaCargaStg] DATETIME2(7) NOT NULL CONSTRAINT DF_dimTerminosVenta_FechaCargaStg DEFAULT (SYSDATETIME()),
    [RunId] INT NULL
    );
END

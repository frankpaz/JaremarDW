IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'stg' AND t.name = 'factVentasEncabezados'
)
BEGIN
    CREATE TABLE stg.factVentasEncabezados (
    [IHDPFX] NVARCHAR(2) NULL,
    [IHDOCN] DECIMAL(8,0) NULL,
    [IHDYR] DECIMAL(2,0) NULL,
    [IHDTYP] DECIMAL(1,0) NULL,
    [SICURR] NVARCHAR(3) NULL,
    [SICNFC] DECIMAL(15,7) NULL,
    [SIGCNV] DECIMAL(15,7) NULL,
    [SITERM] NVARCHAR(2) NULL,
    [SICARR] NVARCHAR(6) NULL,
    [SIROUT] NVARCHAR(6) NULL,
    [IHENDT] DECIMAL(8,0) NULL,
    [IHENTM] DECIMAL(6,0) NULL,
    [IHENUS] NVARCHAR(10) NULL,
    [FechaCargaStg] DATETIME2(7) NOT NULL CONSTRAINT DF_factVentasEncabezados_FechaCargaStg DEFAULT (SYSDATETIME()),
    [RunId] INT NULL
    );
END

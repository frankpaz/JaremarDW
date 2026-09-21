IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'stg' AND t.name = 'dimProducto'
)
BEGIN
    CREATE TABLE stg.dimProducto (
    [IID] NVARCHAR(2) NULL,
    [IPROD] NVARCHAR(35) NULL,
    [IDESC] NVARCHAR(50) NULL,
    [ICLAS] NVARCHAR(2) NULL,
    [IUMS] NVARCHAR(2) NULL,
    [IUMP] NVARCHAR(2) NULL,
    [ILDTE] DECIMAL(8,0) NULL,
    [IMMNDT] DECIMAL(8,0) NULL,
    [IMMNTM] DECIMAL(6,0) NULL,
    [FechaCargaStg] DATETIME2(7) NOT NULL CONSTRAINT DF_dimProducto_FechaCargaStg DEFAULT (SYSDATETIME()),
    [RunId] INT NULL
    );
END

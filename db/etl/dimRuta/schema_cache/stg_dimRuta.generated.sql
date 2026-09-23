IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'stg' AND t.name = 'dimRuta'
)
BEGIN
    CREATE TABLE stg.dimRuta (
    [CCCODE] NVARCHAR(15) NULL,
    [CCDESC] NVARCHAR(30) NULL,
    [CCENDT] DECIMAL(8,0) NULL,
    [CCENTM] DECIMAL(6,0) NULL,
    [CCENUS] NVARCHAR(10) NULL,
    [CCMNDT] DECIMAL(8,0) NULL,
    [CCMNTM] DECIMAL(6,0) NULL,
    [CCMNUS] NVARCHAR(10) NULL,
    [FechaCargaStg] DATETIME2(7) NOT NULL CONSTRAINT DF_dimRuta_FechaCargaStg DEFAULT (SYSDATETIME()),
    [RunId] INT NULL
    );
END

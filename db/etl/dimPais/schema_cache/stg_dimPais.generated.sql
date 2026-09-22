IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'stg' AND t.name = 'dimPais'
)
BEGIN
    CREATE TABLE stg.dimPais (
    [CNCNTY] NVARCHAR(4) NULL,
    [CNLDSC] NVARCHAR(30) NULL,
    [CNSDSC] NVARCHAR(15) NULL,
    [CNLANG] NVARCHAR(3) NULL,
    [CNLUSR] NVARCHAR(10) NULL,
    [CNLDTE] DECIMAL(8,0) NULL,
    [CNLTME] DECIMAL(6,0) NULL,
    [CNCUSR] NVARCHAR(10) NULL,
    [CNCDTE] DECIMAL(8,0) NULL,
    [CNCTME] DECIMAL(6,0) NULL,
    [FechaCargaStg] DATETIME2(7) NOT NULL CONSTRAINT DF_dimPais_FechaCargaStg DEFAULT (SYSDATETIME()),
    [RunId] INT NULL
    );
END

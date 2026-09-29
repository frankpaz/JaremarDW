IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'stg' AND t.name = 'dimLugarBascula'
)
BEGIN
    CREATE TABLE stg.dimLugarBascula (
    [NUMLUG] DECIMAL(5,0) NULL,
    [MOMLUG] NVARCHAR(40) NULL,
    [FechaCargaStg] DATETIME2(7) NOT NULL CONSTRAINT DF_dimLugarBascula_FechaCargaStg DEFAULT (SYSDATETIME()),
    [RunId] INT NULL
    );
END

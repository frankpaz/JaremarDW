IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'stg' AND t.name = 'dimBascula'
)
BEGIN
    CREATE TABLE stg.dimBascula (
    [NUMBAS] DECIMAL(3,0) NULL,
    [MOMBAS] NVARCHAR(35) NULL,
    [FechaCargaStg] DATETIME2(7) NOT NULL CONSTRAINT DF_dimBascula_FechaCargaStg DEFAULT (SYSDATETIME()),
    [RunId] INT NULL
    );
END

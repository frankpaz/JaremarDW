IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'stg' AND t.name = 'dimSanAlejoCliente'
)
BEGIN
    CREATE TABLE stg.dimSanAlejoCliente (
    [CODCIA] DECIMAL(3,0) NULL,
    [CODCLI] DECIMAL(8,0) NULL,
    [NOMCLI] NVARCHAR(80) NULL,
    [DIRCLI] NVARCHAR(80) NULL,
    [FechaCargaStg] DATETIME2(7) NOT NULL CONSTRAINT DF_dimSanAlejoCliente_FechaCargaStg DEFAULT (SYSDATETIME()),
    [RunId] INT NULL
    );
END

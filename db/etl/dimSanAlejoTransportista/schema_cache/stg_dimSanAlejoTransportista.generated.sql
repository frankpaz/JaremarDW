IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'stg' AND t.name = 'dimSanAlejoTransportista'
)
BEGIN
    CREATE TABLE stg.dimSanAlejoTransportista (
    [CODCIA] DECIMAL(3,0) NULL,
    [CODTRA] DECIMAL(5,0) NULL,
    [NOMTRA] NVARCHAR(70) NULL,
    [VALKIL] DECIMAL(12,4) NULL,
    [PRECIO] DECIMAL(12,2) NULL,
    [CODALX] DECIMAL(8,0) NULL,
    [FechaCargaStg] DATETIME2(7) NOT NULL CONSTRAINT DF_dimSanAlejoTransportista_FechaCargaStg DEFAULT (SYSDATETIME()),
    [RunId] INT NULL
    );
END

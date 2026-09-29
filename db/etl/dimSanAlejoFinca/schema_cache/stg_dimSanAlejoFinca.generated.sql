IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'stg' AND t.name = 'dimSanAlejoFinca'
)
BEGIN
    CREATE TABLE stg.dimSanAlejoFinca (
    [CODCIA] DECIMAL(3,0) NULL,
    [FINCA] NVARCHAR(5) NULL,
    [CODSUC] DECIMAL(3,0) NULL,
    [FRENTE] NVARCHAR(50) NULL,
    [EXTEN] DECIMAL(10,3) NULL,
    [DESFIN] NVARCHAR(100) NULL,
    [VARIED] NVARCHAR(50) NULL,
    [PREFFB] DECIMAL(13,2) NULL,
    [NOPLA] NVARCHAR(4) NULL,
    [CIAREL] DECIMAL(3,0) NULL,
    [STATUS] NVARCHAR(1) NULL,
    [FechaCargaStg] DATETIME2(7) NOT NULL CONSTRAINT DF_dimSanAlejoFinca_FechaCargaStg DEFAULT (SYSDATETIME()),
    [RunId] INT NULL
    );
END

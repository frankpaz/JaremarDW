IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'stg' AND t.name = 'dimSanAlejoProductor'
)
BEGIN
    CREATE TABLE stg.dimSanAlejoProductor (
    [CODCIA] DECIMAL(3,0) NULL,
    [CODPRO] DECIMAL(5,0) NULL,
    [NOMPRO] NVARCHAR(80) NULL,
    [UBICA] NVARCHAR(150) NULL,
    [SECTOR] NVARCHAR(4) NULL,
    [ESTADO] DECIMAL(2,0) NULL,
    [TOTHEC] DECIMAL(10,3) NULL,
    [NUMCON] DECIMAL(10,0) NULL,
    [FECCON] DECIMAL(8,0) NULL,
    [FECFIN] DECIMAL(8,0) NULL,
    [CODLOC] DECIMAL(5,0) NULL,
    [CODANT] DECIMAL(5,0) NULL,
    [FechaCargaStg] DATETIME2(7) NOT NULL CONSTRAINT DF_dimSanAlejoProductor_FechaCargaStg DEFAULT (SYSDATETIME()),
    [RunId] INT NULL
    );
END

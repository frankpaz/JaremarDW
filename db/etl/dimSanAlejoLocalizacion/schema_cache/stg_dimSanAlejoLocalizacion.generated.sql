IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'stg' AND t.name = 'dimSanAlejoLocalizacion'
)
BEGIN
    CREATE TABLE stg.dimSanAlejoLocalizacion (
    [CODCIA] DECIMAL(3,0) NULL,
    [CODLOC] DECIMAL(5,0) NULL,
    [ORIGEN] NVARCHAR(80) NULL,
    [DESTIN] NVARCHAR(80) NULL,
    [PRECTM] DECIMAL(13,4) NULL,
    [COSTOK] DECIMAL(13,4) NULL,
    [CODTAR] NVARCHAR(30) NULL,
    [SECTOR] NVARCHAR(4) NULL,
    [CAMPO1] NVARCHAR(30) NULL,
    [MARCA] NVARCHAR(1) NULL,
    [FechaCargaStg] DATETIME2(7) NOT NULL CONSTRAINT DF_dimSanAlejoLocalizacion_FechaCargaStg DEFAULT (SYSDATETIME()),
    [RunId] INT NULL
    );
END

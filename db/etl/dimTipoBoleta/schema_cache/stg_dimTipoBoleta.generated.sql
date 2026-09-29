IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'stg' AND t.name = 'dimTipoBoleta'
)
BEGIN
    CREATE TABLE stg.dimTipoBoleta (
    [BOLETY] DECIMAL(2,0) NULL,
    [DESTYP] NVARCHAR(35) NULL,
    [BENVIO] NVARCHAR(1) NULL,
    [BINOUT] NVARCHAR(1) NULL,
    [BTOLEP] DECIMAL(6,3) NULL,
    [BTOLEN] DECIMAL(6,3) NULL,
    [FechaCargaStg] DATETIME2(7) NOT NULL CONSTRAINT DF_dimTipoBoleta_FechaCargaStg DEFAULT (SYSDATETIME()),
    [RunId] INT NULL
    );
END

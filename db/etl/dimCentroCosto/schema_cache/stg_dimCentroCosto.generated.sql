IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'stg' AND t.name = 'dimCentroCosto'
)
BEGIN
    CREATE TABLE stg.dimCentroCosto (
    [SVID] NVARCHAR(2) NULL,
    [SVSGVL] NVARCHAR(16) NULL,
    [SVLDES] NVARCHAR(30) NULL,
    [SVDATE] DECIMAL(8,0) NULL,
    [SVTIME] DECIMAL(6,0) NULL,
    [FechaCargaStg] DATETIME2(7) NOT NULL CONSTRAINT DF_dimCentroCosto_FechaCargaStg DEFAULT (SYSDATETIME()),
    [RunId] INT NULL
    );
END

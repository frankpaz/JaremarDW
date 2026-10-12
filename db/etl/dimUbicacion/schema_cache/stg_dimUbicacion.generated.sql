IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'stg' AND t.name = 'dimUbicacion'
)
BEGIN
    CREATE TABLE stg.dimUbicacion (
    [WID] NVARCHAR(2) NULL,
    [WWHS] NVARCHAR(3) NULL,
    [WLOC] NVARCHAR(10) NULL,
    [WDESC] NVARCHAR(30) NULL,
    [WCYCI] DECIMAL(3,0) NULL,
    [LMPRF] NVARCHAR(10) NULL,
    [WLTYP] NVARCHAR(1) NULL,
    [WZONE] NVARCHAR(3) NULL,
    [WCONC] DECIMAL(11,2) NULL,
    [WALLC] NVARCHAR(1) NULL,
    [WFLOC] NVARCHAR(1) NULL,
    [FechaCargaStg] DATETIME2(7) NOT NULL CONSTRAINT DF_dimUbicacion_FechaCargaStg DEFAULT (SYSDATETIME()),
    [RunId] INT NULL
    );
END

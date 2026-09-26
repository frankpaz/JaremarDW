IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'stg' AND t.name = 'dimViaje'
)
BEGIN
    CREATE TABLE stg.dimViaje (
    [VCODPA] DECIMAL(4,0) NULL,
    [VDESC] NVARCHAR(40) NULL,
    [VPAGAM] DECIMAL(8,2) NULL,
    [VPAGAA] DECIMAL(8,2) NULL,
    [VUSUAG] NVARCHAR(10) NULL,
    [VFECHG] DECIMAL(8,0) NULL,
    [VHORAG] DECIMAL(6,0) NULL,
    [VUSUAM] NVARCHAR(10) NULL,
    [VFECHM] DECIMAL(8,0) NULL,
    [VHORAM] DECIMAL(8,0) NULL,
    [VSTS] NVARCHAR(1) NULL,
    [FechaCargaStg] DATETIME2(7) NOT NULL CONSTRAINT DF_dimViaje_FechaCargaStg DEFAULT (SYSDATETIME()),
    [RunId] INT NULL
    );
END

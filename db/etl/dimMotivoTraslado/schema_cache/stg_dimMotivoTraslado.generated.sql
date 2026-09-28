IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'stg' AND t.name = 'dimMotivoTraslado'
)
BEGIN
    CREATE TABLE stg.dimMotivoTraslado (
    [D901MT] DECIMAL(2,0) NULL,
    [D901DM] NVARCHAR(100) NULL,
    [FechaCargaStg] DATETIME2(7) NOT NULL CONSTRAINT DF_dimMotivoTraslado_FechaCargaStg DEFAULT (SYSDATETIME()),
    [RunId] INT NULL
    );
END

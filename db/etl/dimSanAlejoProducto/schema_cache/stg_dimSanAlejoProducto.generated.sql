IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'stg' AND t.name = 'dimSanAlejoProducto'
)
BEGIN
    CREATE TABLE stg.dimSanAlejoProducto (
    [COPROD] NVARCHAR(5) NULL,
    [NOPROD] NVARCHAR(100) NULL,
    [CODALT] NVARCHAR(35) NULL,
    [UNIMED] NVARCHAR(3) NULL,
    [PREPRO] DECIMAL(15,4) NULL,
    [CERTIF] NVARCHAR(20) NULL,
    [FechaCargaStg] DATETIME2(7) NOT NULL CONSTRAINT DF_dimSanAlejoProducto_FechaCargaStg DEFAULT (SYSDATETIME()),
    [RunId] INT NULL
    );
END

-- 189: dw.dimBascula -- dimension Gold (SCD Tipo 1), a partir de [int].dimBascula.
-- La usa dw.factBasculaBufalo (BasculaKey, via BASCIA de PROLXUSRF.BASMASTNN).

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'dimBascula'
)
BEGIN
    CREATE TABLE dw.dimBascula (
        BasculaKey      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_dimBascula PRIMARY KEY,
        CodigoBascula   INT           NOT NULL,
        NombreBascula   NVARCHAR(35)  NULL,
        EsVigente       BIT           NOT NULL CONSTRAINT DF_dw_dimBascula_EsVigente DEFAULT (1),
        HashDiff        BINARY(32)    NOT NULL,
        FechaCargaDw    DATETIME2(7)  NOT NULL CONSTRAINT DF_dw_dimBascula_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId           INT           NULL,
        CONSTRAINT UQ_dw_dimBascula_Codigo UNIQUE (CodigoBascula)
    );
END
GO

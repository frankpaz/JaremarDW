-- 187: [int].dimBascula -- version Silver de stg.dimBascula (PROLXUSRF.BASCULAS, catalogo de basculas).
-- Llave de negocio NUMBAS (4 basculas al 2026-09-29).

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'dimBascula'
)
BEGIN
    CREATE TABLE [int].dimBascula (
        NUMBAS          INT           NOT NULL CONSTRAINT PK_Int_dimBascula PRIMARY KEY,
        MOMBAS          NVARCHAR(35)  NULL,
        EsVigente       BIT           NOT NULL CONSTRAINT DF_Int_dimBascula_EsVigente DEFAULT (1),
        HashDiff        BINARY(32)    NOT NULL,
        FechaCargaInt   DATETIME2(7)  NOT NULL CONSTRAINT DF_Int_dimBascula_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId           INT           NULL
    );
END
GO

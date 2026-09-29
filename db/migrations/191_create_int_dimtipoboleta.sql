-- 191: [int].dimTipoBoleta -- version Silver de stg.dimTipoBoleta (PROLXUSRF.BASBOLTY2, tipos de boleta de bascula, version 2 con tolerancias).
-- Llave de negocio BOLETY (8 tipos al 2026-09-29).

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'dimTipoBoleta'
)
BEGIN
    CREATE TABLE [int].dimTipoBoleta (
        BOLETY          INT           NOT NULL CONSTRAINT PK_Int_dimTipoBoleta PRIMARY KEY,
        DESTYP          NVARCHAR(35)  NULL,
        BENVIO          NVARCHAR(1)   NULL,
        BINOUT          NVARCHAR(1)   NULL,
        BTOLEP          DECIMAL(6,3)  NULL,
        BTOLEN          DECIMAL(6,3)  NULL,
        EsVigente       BIT           NOT NULL CONSTRAINT DF_Int_dimTipoBoleta_EsVigente DEFAULT (1),
        HashDiff        BINARY(32)    NOT NULL,
        FechaCargaInt   DATETIME2(7)  NOT NULL CONSTRAINT DF_Int_dimTipoBoleta_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId           INT           NULL
    );
END
GO

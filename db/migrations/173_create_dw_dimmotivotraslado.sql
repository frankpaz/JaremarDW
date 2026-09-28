-- 173: dw.dimMotivoTraslado -- dimension Gold (SCD Tipo 1), a partir de [int].dimMotivoTraslado.
-- La usa dw.factGuiasRemision (MotivoTrasladoKey, via D100MT de PROLXUSRF.UNDIS100).

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'dimMotivoTraslado'
)
BEGIN
    CREATE TABLE dw.dimMotivoTraslado (
        MotivoTrasladoKey          INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_dimMotivoTraslado PRIMARY KEY,
        CodigoMotivoTraslado       INT           NOT NULL,
        DescripcionMotivoTraslado  NVARCHAR(100) NULL,
        EsVigente                  BIT           NOT NULL CONSTRAINT DF_dw_dimMotivoTraslado_EsVigente DEFAULT (1),
        HashDiff                   BINARY(32)    NOT NULL,
        FechaCargaDw               DATETIME2(7)  NOT NULL CONSTRAINT DF_dw_dimMotivoTraslado_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId                      INT           NULL,
        CONSTRAINT UQ_dw_dimMotivoTraslado_Codigo UNIQUE (CodigoMotivoTraslado)
    );
END
GO

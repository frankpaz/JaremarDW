-- 171: [int].dimMotivoTraslado -- version Silver de stg.dimMotivoTraslado (PROLXUSRF.UNDIS901).
-- Llave de negocio D901MT (motivo de traslado de las guias de remision; 12 motivos al 2026-09-28).

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'dimMotivoTraslado'
)
BEGIN
    CREATE TABLE [int].dimMotivoTraslado (
        D901MT          INT           NOT NULL CONSTRAINT PK_Int_dimMotivoTraslado PRIMARY KEY,
        D901DM          NVARCHAR(100) NULL,
        EsVigente       BIT           NOT NULL CONSTRAINT DF_Int_dimMotivoTraslado_EsVigente DEFAULT (1),
        HashDiff        BINARY(32)    NOT NULL,
        FechaCargaInt   DATETIME2(7)  NOT NULL CONSTRAINT DF_Int_dimMotivoTraslado_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId           INT           NULL
    );
END
GO

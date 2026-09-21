-- 007: [int].dimProducto -- version Silver de stg.dimProducto.
-- Mantiene los codigos AS400 originales (IPROD, IDESC...) por no tener el
-- diccionario de datos completo -- solo corrige tipos (fechas/hora reales en
-- vez de decimales AAAAMMDD/HHMMSS), deduplica por IPROD (llave de negocio) y
-- agrega HashDiff para permitir MERGE incremental barato.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'dimProducto'
)
BEGIN
    CREATE TABLE [int].dimProducto (
        IPROD           NVARCHAR(70)  NOT NULL CONSTRAINT PK_Int_dimProducto PRIMARY KEY,
        IDESC           NVARCHAR(100) NULL,
        ICLAS           NVARCHAR(4)   NULL,
        IUMS            NVARCHAR(4)   NULL,
        IUMP            NVARCHAR(4)   NULL,
        ILDTE           DATE          NULL,
        IMMNDT          DATE          NULL,
        IMMNTM          TIME(0)       NULL,
        EsVigente       BIT           NOT NULL CONSTRAINT DF_Int_dimProducto_EsVigente DEFAULT (1),
        HashDiff        BINARY(32)    NOT NULL,
        FechaCargaInt   DATETIME2(7)  NOT NULL CONSTRAINT DF_Int_dimProducto_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId           INT           NULL
    );
END
GO

-- 195: [int].dimLugarBascula -- version Silver de stg.dimLugarBascula (PROLXUSRF.BASLUGAR, lugares de origen/destino de las boletas).
-- Llave de negocio NUMLUG (1.434 filas, 1.432 codigos: 1039 y 1290 vienen repetidos e identicos al 2026-09-29).

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'dimLugarBascula'
)
BEGIN
    CREATE TABLE [int].dimLugarBascula (
        NUMLUG          INT           NOT NULL CONSTRAINT PK_Int_dimLugarBascula PRIMARY KEY,
        MOMLUG          NVARCHAR(40)  NULL,
        EsVigente       BIT           NOT NULL CONSTRAINT DF_Int_dimLugarBascula_EsVigente DEFAULT (1),
        HashDiff        BINARY(32)    NOT NULL,
        FechaCargaInt   DATETIME2(7)  NOT NULL CONSTRAINT DF_Int_dimLugarBascula_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId           INT           NULL
    );
END
GO

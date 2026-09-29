-- 197: dw.dimLugarBascula -- dimension Gold (SCD Tipo 1), a partir de [int].dimLugarBascula.
-- La usa dw.factBasculaBufalo dos veces: LugarOrigenKey (ORIGEN) y LugarDestinoKey (NUMLUGAR).

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'dimLugarBascula'
)
BEGIN
    CREATE TABLE dw.dimLugarBascula (
        LugarBasculaKey    INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_dimLugarBascula PRIMARY KEY,
        CodigoLugar        INT           NOT NULL,
        DescripcionLugar   NVARCHAR(40)  NULL,
        EsVigente          BIT           NOT NULL CONSTRAINT DF_dw_dimLugarBascula_EsVigente DEFAULT (1),
        HashDiff           BINARY(32)    NOT NULL,
        FechaCargaDw       DATETIME2(7)  NOT NULL CONSTRAINT DF_dw_dimLugarBascula_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId              INT           NULL,
        CONSTRAINT UQ_dw_dimLugarBascula_Codigo UNIQUE (CodigoLugar)
    );
END
GO

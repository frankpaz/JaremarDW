-- 193: dw.dimTipoBoleta -- dimension Gold (SCD Tipo 1), a partir de [int].dimTipoBoleta.
-- La usa dw.factBasculaBufalo (TipoBoletaKey, via BOLETY).

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'dimTipoBoleta'
)
BEGIN
    CREATE TABLE dw.dimTipoBoleta (
        TipoBoletaKey            INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_dimTipoBoleta PRIMARY KEY,
        CodigoTipoBoleta         INT           NOT NULL,
        DescripcionTipoBoleta    NVARCHAR(35)  NULL,
        IndicadorEnvio           NVARCHAR(1)   NULL,
        IndicadorIngresoSalida   NVARCHAR(1)   NULL,
        ToleranciaPositivaPct    DECIMAL(6,3)  NULL,
        ToleranciaNegativaPct    DECIMAL(6,3)  NULL,
        EsVigente                BIT           NOT NULL CONSTRAINT DF_dw_dimTipoBoleta_EsVigente DEFAULT (1),
        HashDiff                 BINARY(32)    NOT NULL,
        FechaCargaDw             DATETIME2(7)  NOT NULL CONSTRAINT DF_dw_dimTipoBoleta_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId                    INT           NULL,
        CONSTRAINT UQ_dw_dimTipoBoleta_Codigo UNIQUE (CodigoTipoBoleta)
    );
END
GO

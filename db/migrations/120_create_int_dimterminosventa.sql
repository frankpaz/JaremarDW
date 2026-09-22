-- 120: [int].dimTerminosVenta -- version Silver de stg.dimTerminosVenta.
-- Fuente: PROLX835F.RTM, TMID='TM' ("A/R Terms Master File", catalogo de
-- terminos de pago de ventas, definido POR EMPRESA). Distinto del catalogo
-- de compras (AVT, ver dimTerminosCompra) -- no son intercambiables.
-- Llave de negocio TMCMPN+TMTERM (107 filas, unica verificada). Patron
-- FULL + SCD Tipo 1. No hay columna de auditoria para tiebreak de dedup
-- (tabla de configuracion pequena, sin fechas de entrada/modificacion).
-- Se preservan los nombres de columna originales del AS400; el renombre a
-- nombre de negocio ocurre solo en dw.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'dimTerminosVenta'
)
BEGIN
    CREATE TABLE [int].dimTerminosVenta (
        TMCMPN          DECIMAL(2,0)  NOT NULL,
        TMTERM          NVARCHAR(2)   NOT NULL,
        TMDESC          NVARCHAR(15)  NULL,
        TMDUE           DECIMAL(5,0)  NULL,
        TMTAXD          NVARCHAR(1)   NULL,
        TMBBTA          NVARCHAR(1)   NULL,
        TMCWO           NVARCHAR(1)   NULL,
        EsVigente       BIT           NOT NULL CONSTRAINT DF_Int_dimTerminosVenta_EsVigente DEFAULT (1),
        HashDiff        BINARY(32)    NOT NULL,
        FechaCargaInt   DATETIME2(7)  NOT NULL CONSTRAINT DF_Int_dimTerminosVenta_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId           INT           NULL,
        CONSTRAINT PK_Int_dimTerminosVenta PRIMARY KEY (TMCMPN, TMTERM)
    );
END
GO

-- 124: [int].dimTerminosCompra -- version Silver de stg.dimTerminosCompra.
-- Fuente: PROLX835F.AVT, VTMID='VT' ("Vendor Terms", catalogo de terminos
-- de pago de compras, GLOBAL -- sin distincion por empresa, a diferencia
-- de RTM/dimTerminosVenta que si es por empresa). No son intercambiables.
-- Llave de negocio VTERM (12 filas, unica verificada). Patron
-- FULL + SCD Tipo 1. No hay columna de auditoria para tiebreak de dedup.
-- Se preservan los nombres de columna originales del AS400; el renombre a
-- nombre de negocio ocurre solo en dw.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'dimTerminosCompra'
)
BEGIN
    CREATE TABLE [int].dimTerminosCompra (
        VTERM           NVARCHAR(2)   NOT NULL CONSTRAINT PK_Int_dimTerminosCompra PRIMARY KEY,
        VTMDSC          NVARCHAR(15)  NULL,
        VTMDDY          DECIMAL(3,0)  NULL,
        VTTAXD          NVARCHAR(1)   NULL,
        EsVigente       BIT           NOT NULL CONSTRAINT DF_Int_dimTerminosCompra_EsVigente DEFAULT (1),
        HashDiff        BINARY(32)    NOT NULL,
        FechaCargaInt   DATETIME2(7)  NOT NULL CONSTRAINT DF_Int_dimTerminosCompra_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId           INT           NULL
    );
END
GO

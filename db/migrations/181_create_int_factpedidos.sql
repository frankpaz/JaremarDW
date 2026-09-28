-- 181: [int].factPedidos -- version Silver de stg.factPedidos (PROLXUSRF.UNDIS002, detalle de
-- pedidos de venta: lo pedido antes de facturar). Una fila por orden x linea. SIN llave unica:
-- CIA+ORD+LIN se repite en ~0,1 % de las filas y el origen no tiene PK, indices ni fecha de
-- modificacion (discovery 2026-09-28). Igual que factGuiasRemision (175): no hay PK ni HashDiff,
-- la carga reemplaza rangos de D02FEC (fecha de la orden) y el indice clustered va sobre ella.
-- Historico desde 2026-01-01. Se conservan los nombres y tipos numericos del AS400; D02FEC
-- (AAAAMMDD) -> DATE y D02HOR (HHMMSS) -> TIME(0), con 0 -> NULL. No se cargan D02DSP (siempre
-- 'BBL') ni D02LTE/D02LTR (vacios en toda la tabla).

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'factPedidos'
)
BEGIN
    CREATE TABLE [int].factPedidos (
        D02CIA          DECIMAL(2,0)   NOT NULL,
        D02ORD          DECIMAL(8,0)   NOT NULL,
        D02CLI          DECIMAL(8,0)   NULL,
        D02LIN          DECIMAL(4,0)   NULL,
        D02PRO          NVARCHAR(35)   NULL,
        D02CAN          DECIMAL(11,3)  NULL,
        D02PES          DECIMAL(12,2)  NULL,
        D02ALM          NVARCHAR(3)    NULL,
        D02LOC          NVARCHAR(10)   NULL,
        D02UM           NVARCHAR(2)    NULL,
        D02REF          NVARCHAR(15)   NULL,
        D02CON          DECIMAL(6,0)   NULL,
        D02DSR          NVARCHAR(6)    NULL,
        D02DSS          NVARCHAR(6)    NULL,
        D02DST          NVARCHAR(6)    NULL,
        D02MAR          NVARCHAR(1)    NULL,
        D02FEC          DATE           NOT NULL,
        D02HOR          TIME(0)        NULL,
        FechaCargaInt   DATETIME2(7)   NOT NULL CONSTRAINT DF_Int_factPedidos_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId           INT            NULL
    );
    CREATE CLUSTERED INDEX CIX_Int_factPedidos_D02FEC ON [int].factPedidos (D02FEC);
    CREATE INDEX IX_Int_factPedidos_FechaCargaInt ON [int].factPedidos (FechaCargaInt) INCLUDE (D02FEC);
END
GO

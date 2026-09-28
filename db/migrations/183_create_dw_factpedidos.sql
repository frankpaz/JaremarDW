-- 183: dw.factPedidos -- fact Gold de pedidos de venta (PROLXUSRF.UNDIS002), una fila por
-- orden x linea. El origen no documenta ninguna columna: los nombres de negocio los definio el
-- usuario (2026-09-28). Sin llave de negocio unica (ver 181): PedidoKey es solo sustituta y
-- cambia cuando se reemplaza la ventana de fechas; no usarla como referencia estable.
-- NumeroOrden cruza con dw.factVentas.NumeroOrden (pedido vs facturado).
-- FKs opcionales (LEFT JOIN): EmpresaKey, ClienteKey, ProductoKey y RutaKey (via CodigoRuta =
-- D02DSR; 365 de 366 codigos existen en dimRuta). CodigoRuta1 (D02DSS) NO es del catalogo de
-- rutas (solo 21 de 705 valores coinciden) y CodigoRuta2 (D02DST) vale '000000' en todo 2026.
-- MarcaProceso: 'P' o NULL; su significado no esta confirmado (NULL no equivale a pendiente de
-- facturar: esas ordenes estan facturadas en un 99,9 %).

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'factPedidos'
)
BEGIN
    CREATE TABLE dw.factPedidos (
        PedidoKey            BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_factPedidos PRIMARY KEY NONCLUSTERED,
        EmpresaKey           INT            NULL CONSTRAINT FK_dw_factPedidos_dimEmpresas REFERENCES dw.dimEmpresas(EmpresaKey),
        ClienteKey           INT            NULL CONSTRAINT FK_dw_factPedidos_dimCliente REFERENCES dw.dimCliente(ClienteKey),
        ProductoKey          INT            NULL CONSTRAINT FK_dw_factPedidos_dimProducto REFERENCES dw.dimProducto(ProductoKey),
        RutaKey              INT            NULL CONSTRAINT FK_dw_factPedidos_dimRuta REFERENCES dw.dimRuta(RutaKey),
        CodigoEmpresa        DECIMAL(2,0)   NOT NULL,
        NumeroOrden          DECIMAL(8,0)   NOT NULL,
        CodigoCliente        DECIMAL(8,0)   NULL,
        NumeroLinea          DECIMAL(4,0)   NULL,
        CodigoProducto       NVARCHAR(35)   NULL,
        Cantidad             DECIMAL(11,3)  NULL,
        Peso                 DECIMAL(12,2)  NULL,
        CodigoAlmacen        NVARCHAR(3)    NULL,
        CodigoLocalidad      NVARCHAR(10)   NULL,
        UnidadMedida         NVARCHAR(2)    NULL,
        NumeroReferencia     NVARCHAR(15)   NULL,
        NumeroConsolidacion  DECIMAL(6,0)   NULL,
        CodigoRuta           NVARCHAR(6)    NULL,
        CodigoRuta1          NVARCHAR(6)    NULL,
        CodigoRuta2          NVARCHAR(6)    NULL,
        MarcaProceso         NVARCHAR(1)    NULL,
        FechaCreacion        DATE           NOT NULL,
        HoraCreacion         TIME(0)        NULL,
        FechaCargaDw         DATETIME2(7)   NOT NULL CONSTRAINT DF_dw_factPedidos_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId                INT            NULL
    );
    CREATE CLUSTERED INDEX CIX_dw_factPedidos_FechaCreacion ON dw.factPedidos (FechaCreacion);
    CREATE INDEX IX_dw_factPedidos_Orden ON dw.factPedidos (CodigoEmpresa, NumeroOrden);
    CREATE INDEX IX_dw_factPedidos_NumeroOrden ON dw.factPedidos (NumeroOrden);
END
GO

-- 106: dw.factVentas -- fact Gold (nombres de negocio segun diccionario de
-- campos real de SIL/SIH confirmado por el usuario, 2026-09-22). FKs a
-- dimEmpresas/dimProducto resueltas via LEFT JOIN (igual criterio que los
-- facts de Solar: FK opcional).
-- ILPCST se mantiene con su nombre AS400 crudo (no renombrado): el usuario
-- decidio explicitamente (2026-09-22) no confirmar que sea "costo de linea"
-- pese a la evidencia estadistica, y dejarlo neutro hasta confirmar con el
-- equipo de datos.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'factVentas'
)
BEGIN
    CREATE TABLE dw.factVentas (
        VentaKey        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_factVentas PRIMARY KEY,
        EmpresaKey      INT           NULL CONSTRAINT FK_dw_factVentas_dimEmpresas REFERENCES dw.dimEmpresas(EmpresaKey),
        ProductoKey     INT           NULL CONSTRAINT FK_dw_factVentas_dimProducto REFERENCES dw.dimProducto(ProductoKey),
        NumeroEmpresa             DECIMAL(2,0)     NOT NULL,
        PrefijoDocumento          NVARCHAR(2)      NOT NULL,
        NumeroDocumento           DECIMAL(8,0)     NOT NULL,
        AnioDocumento             DECIMAL(2,0)     NOT NULL,
        TipoDocumento             DECIMAL(1,0)     NOT NULL,
        NumeroLinea               DECIMAL(4,0)     NOT NULL,
        NumeroSecuencia           DECIMAL(4,0)     NULL,
        NumeroDocumentoOriginal   DECIMAL(8,0)     NULL,
        NumeroOrden               DECIMAL(8,0)     NULL,
        FechaUltimaTransaccion    DATE             NULL,
        FechaEnvio                DATE             NULL,
        CodigoProducto            NVARCHAR(35)     NULL,
        NumeroCliente             DECIMAL(8,0)     NULL,
        NumeroClienteFacturacion  DECIMAL(8,0)     NULL,
        Bodega                    NVARCHAR(3)      NULL,
        TipoLinea                 NVARCHAR(1)      NULL,
        ClaseOrden                DECIMAL(3,0)     NULL,
        Cantidad                  DECIMAL(11,3)    NULL,
        CantidadUMVenta           DECIMAL(11,3)    NULL,
        PrecioNetoStocking        DECIMAL(19,7)    NULL,
        PrecioNetoVenta           DECIMAL(19,7)    NULL,
        PrecioListaTransaccion    DECIMAL(14,4)    NULL,
        PrecioListaBase           DECIMAL(14,4)    NULL,
        MontoExtendido            DECIMAL(15,2)    NULL,
        MontoIngreso              DECIMAL(15,2)    NULL,
        ILPCST                    DECIMAL(15,5)    NULL,
        UnidadMedida              NVARCHAR(2)      NULL,
        UnidadMedidaVentaOriginal NVARCHAR(2)      NULL,
        UnidadMedidaPesoCatch     NVARCHAR(2)      NULL,
        CodigoImpuesto1           NVARCHAR(5)      NULL,
        MontoImpuesto1            DECIMAL(17,4)    NULL,
        CodigoImpuesto2           NVARCHAR(5)      NULL,
        MontoImpuesto2            DECIMAL(17,4)    NULL,
        Vendedor1                 DECIMAL(6,0)     NULL,
        Vendedor3                 DECIMAL(6,0)     NULL,
        CodigoComisionCliente     NVARCHAR(2)      NULL,
        OrdenCompraCliente        NVARCHAR(23)     NULL,
        NumeroConsolidacion       DECIMAL(6,0)     NULL,
        CodigoFuentePrecioNeto    NVARCHAR(2)      NULL,
        CodigoFuentePrecioLista   NVARCHAR(2)      NULL,
        InstalacionPrecio         NVARCHAR(3)      NULL,
        GrupoEmpaque              DECIMAL(8,0)     NULL,
        CodigoMoneda              NVARCHAR(3)      NULL,
        TasaCambioMoneda          DECIMAL(15,7)    NULL,
        TasaCambioGlobal          DECIMAL(15,7)    NULL,
        CodigoTerminos            NVARCHAR(2)      NULL,
        Transportista             NVARCHAR(6)      NULL,
        Ruta                      NVARCHAR(6)      NULL,
        FechaCreacion             DATE             NULL,
        HoraCreacion              TIME(0)          NULL,
        UsuarioCreacion           NVARCHAR(10)     NULL,
        EsVigente       BIT           NOT NULL CONSTRAINT DF_dw_factVentas_EsVigente DEFAULT (1),
        HashDiff        BINARY(32)    NOT NULL,
        FechaCargaDw    DATETIME2(7)  NOT NULL CONSTRAINT DF_dw_factVentas_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId           INT           NULL,
        CONSTRAINT UQ_dw_factVentas_Linea UNIQUE (NumeroEmpresa, PrefijoDocumento, NumeroDocumento, AnioDocumento, TipoDocumento, NumeroLinea)
    );
END
GO

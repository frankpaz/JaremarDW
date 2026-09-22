-- 118: dw.factCompras -- fact Gold, a partir de [int].factCompras. FKs a
-- dimEmpresas/dimProveedor resueltas via LEFT JOIN (igual criterio que
-- factVentas). Incremental puro, sin EsVigente/SCD (no aplica: no se
-- extrae el origen completo en cada corrida, ver 116).

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'factCompras'
)
BEGIN
    CREATE TABLE dw.factCompras (
        CompraKey       INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_factCompras PRIMARY KEY,
        EmpresaKey      INT           NULL CONSTRAINT FK_dw_factCompras_dimEmpresas REFERENCES dw.dimEmpresas(EmpresaKey),
        ProveedorKey    INT           NULL CONSTRAINT FK_dw_factCompras_dimProveedor REFERENCES dw.dimProveedor(ProveedorKey),
        NumeroEmpresa             DECIMAL(2,0)     NOT NULL,
        PrefijoDocumento          NVARCHAR(2)      NOT NULL,
        AnioDocumento             DECIMAL(2,0)     NOT NULL,
        NumeroSecuenciaDocumento  DECIMAL(8,0)     NOT NULL,
        NumeroLinea               DECIMAL(4,0)     NOT NULL,
        NumeroProveedor           DECIMAL(8,0)     NULL,
        NumeroFacturaReferencia   NVARCHAR(10)     NULL,
        TipoLinea                 NVARCHAR(1)      NULL,
        FechaContable             DATE             NULL,
        MontoPago                 DECIMAL(15,2)    NULL,
        MontoPagoBase             DECIMAL(15,2)    NULL,
        DescripcionFactura        NVARCHAR(25)     NULL,
        UsuarioCreacion           NVARCHAR(10)     NULL,
        FechaCreacion             DATE             NULL,
        HoraCreacion              TIME(0)          NULL,
        CodigoRazon               NVARCHAR(5)      NULL,
        ProveedorPagoA            DECIMAL(8,0)     NULL,
        CodigoBanco               NVARCHAR(3)      NULL,
        CodigoMoneda              NVARCHAR(3)      NULL,
        FacturaEnRetencion        NVARCHAR(1)      NULL,
        FechaFactura              DATE             NULL,
        FechaVencimiento          DATE             NULL,
        FechaDescuento            DATE             NULL,
        MontoFacturaActual        DECIMAL(15,2)    NULL,
        MontoPagadoActual         DECIMAL(15,2)    NULL,
        SaldoPendiente            DECIMAL(15,2)    NULL,
        NumeroOrdenCompra         DECIMAL(8,0)     NULL,
        CodigoTerminos            NVARCHAR(2)      NULL,
        EstadoFactura             NVARCHAR(1)      NULL,
        BanderaSeleccionPago      NVARCHAR(1)      NULL,
        TasaImpuestoMaxima        DECIMAL(7,4)     NULL,
        MontoImpuesto             DECIMAL(15,2)    NULL,
        CodigoImpuestoProveedor   NVARCHAR(5)      NULL,
        TipoPago                  NVARCHAR(1)      NULL,
        HashDiff        BINARY(32)    NOT NULL,
        FechaCargaDw    DATETIME2(7)  NOT NULL CONSTRAINT DF_dw_factCompras_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId           INT           NULL,
        CONSTRAINT UQ_dw_factCompras_Linea UNIQUE (NumeroEmpresa, PrefijoDocumento, AnioDocumento, NumeroSecuenciaDocumento, NumeroLinea)
    );
END
GO

-- 177: dw.factGuiasRemision -- fact Gold de guias de remision (PROLXUSRF.UNDIS100),
-- una fila por guia x factura x producto. Nombres de negocio tomados de COLUMN_TEXT del
-- origen. Sin llave de negocio unica (ver 175): GuiaRemisionKey es solo sustituta, y
-- cambia cuando se reemplaza la ventana de fechas; no usarla como referencia estable.
-- La guia se identifica con NumeroEmpresa + PrefijoGuia + CentroImpresion + Seccion +
-- TipoDocumento + NumeroGuia.
-- FKs opcionales (LEFT JOIN, igual criterio que factVentas): EmpresaKey, ClienteKey,
-- ProductoKey (D100PR trae texto libre en guias de bascula, ~8 % sin match),
-- VehiculoKey (camion) y MotivoTrasladoKey. NumeroEnvio y NumeroFactura quedan como
-- columnas para cruzar con dw.factEnvios y dw.factVentas.
-- Estado: 'VALIDO' / 'ANULAD' tal como viene; los reportes deben filtrar las anuladas.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'factGuiasRemision'
)
BEGIN
    CREATE TABLE dw.factGuiasRemision (
        GuiaRemisionKey          BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_factGuiasRemision PRIMARY KEY NONCLUSTERED,
        EmpresaKey               INT            NULL CONSTRAINT FK_dw_factGuiasRemision_dimEmpresas REFERENCES dw.dimEmpresas(EmpresaKey),
        ClienteKey               INT            NULL CONSTRAINT FK_dw_factGuiasRemision_dimCliente REFERENCES dw.dimCliente(ClienteKey),
        ProductoKey              INT            NULL CONSTRAINT FK_dw_factGuiasRemision_dimProducto REFERENCES dw.dimProducto(ProductoKey),
        VehiculoKey              INT            NULL CONSTRAINT FK_dw_factGuiasRemision_dimVehiculo REFERENCES dw.dimVehiculo(VehiculoKey),
        MotivoTrasladoKey        INT            NULL CONSTRAINT FK_dw_factGuiasRemision_dimMotivoTraslado REFERENCES dw.dimMotivoTraslado(MotivoTrasladoKey),
        NumeroEmpresa            INT            NOT NULL,
        CodigoOrigen             INT            NULL,
        PrefijoGuia              NVARCHAR(2)    NULL,
        CentroImpresion          INT            NULL,
        Seccion                  INT            NULL,
        TipoDocumento            INT            NULL,
        NumeroGuia               INT            NOT NULL,
        CodigoCAI                NVARCHAR(40)   NULL,
        RangoAutorizadoInicio    INT            NULL,
        RangoAutorizadoFin       INT            NULL,
        FechaInicioAutorizacion  DATE           NULL,
        FechaFinAutorizacion     DATE           NULL,
        NumeroEnvio              INT            NULL,
        CodigoMotivoTraslado     INT            NULL,
        FechaEnvio               DATE           NULL,
        HoraEnvio                TIME(0)        NULL,
        CodigoCamion             NVARCHAR(6)    NULL,
        CodigoRemolque           NVARCHAR(6)    NULL,
        NumeroManifiesto         INT            NULL,
        NumeroCliente            INT            NULL,
        RTNCliente               NVARCHAR(16)   NULL,
        NumeroPedido             INT            NULL,
        NumeroFactura            INT            NULL,
        FechaFactura             DATE           NULL,
        CodigoProducto           NVARCHAR(35)   NULL,
        Cantidad                 DECIMAL(15,3)  NULL,
        PesoKilos                DECIMAL(15,2)  NULL,
        ValorNeto                DECIMAL(15,2)  NULL,
        Pantalla                 NVARCHAR(10)   NULL,
        Usuario                  NVARCHAR(10)   NULL,
        FechaRegistro            DATE           NOT NULL,
        HoraRegistro             TIME(0)        NULL,
        Estado                   NVARCHAR(6)    NULL,
        FechaCargaDw             DATETIME2(7)   NOT NULL CONSTRAINT DF_dw_factGuiasRemision_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId                    INT            NULL
    );
    CREATE CLUSTERED INDEX CIX_dw_factGuiasRemision_FechaRegistro ON dw.factGuiasRemision (FechaRegistro);
    CREATE INDEX IX_dw_factGuiasRemision_Guia ON dw.factGuiasRemision (NumeroEmpresa, PrefijoGuia, NumeroGuia);
    CREATE INDEX IX_dw_factGuiasRemision_NumeroEnvio ON dw.factGuiasRemision (NumeroEnvio);
    CREATE INDEX IX_dw_factGuiasRemision_NumeroFactura ON dw.factGuiasRemision (NumeroFactura);
END
GO

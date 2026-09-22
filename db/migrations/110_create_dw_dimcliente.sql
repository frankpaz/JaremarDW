-- 110: dw.dimCliente -- dimension Gold (SCD Tipo 1), a partir de
-- [int].dimCliente. Nombres de negocio segun diccionario de campos real de
-- RCM (2026-09-22, via db/discovery/discover_columnas.py).

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'dimCliente'
)
BEGIN
    CREATE TABLE dw.dimCliente (
        ClienteKey                  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_dimCliente PRIMARY KEY,
        CodigoCliente                DECIMAL(8,0)  NOT NULL,
        NombreCliente                NVARCHAR(50)  NULL,
        ClaveBusqueda                NVARCHAR(20)  NULL,
        Direccion1                   NVARCHAR(50)  NULL,
        Direccion2                   NVARCHAR(50)  NULL,
        Direccion3                   NVARCHAR(50)  NULL,
        CodigoEstado                 NVARCHAR(3)   NULL,
        CodigoPostal                 NVARCHAR(9)   NULL,
        CodigoPais                   NVARCHAR(4)   NULL,
        TipoCliente                  NVARCHAR(4)   NULL,
        NumeroEmpresa                DECIMAL(2,0)  NULL,
        NumeroClienteCorporativo     DECIMAL(8,0)  NULL,
        RegionPromocion              NVARCHAR(6)   NULL,
        RegionPrecio                 NVARCHAR(6)   NULL,
        CodigoGrupo1                 NVARCHAR(8)   NULL,
        Vendedor                     DECIMAL(6,0)  NULL,
        CodigoTerminos               NVARCHAR(2)   NULL,
        CodigoImpuesto               NVARCHAR(5)   NULL,
        NumeroIdentificacionFiscal   NVARCHAR(12)  NULL,
        CodigoPago                   NVARCHAR(1)   NULL,
        CodigoMoneda                 NVARCHAR(3)   NULL,
        BodegaDefecto                NVARCHAR(3)   NULL,
        Ruta                         NVARCHAR(6)   NULL,
        TipoOrdenDefecto             NVARCHAR(1)   NULL,
        NombreContacto               NVARCHAR(30)  NULL,
        Telefono                     NVARCHAR(25)  NULL,
        LimiteCredito                DECIMAL(15,2) NULL,
        DiasLimiteCredito            DECIMAL(3,0)  NULL,
        PromedioDiasPago             DECIMAL(3,0)  NULL,
        PromedioFactura              DECIMAL(15,2) NULL,
        FechaUltimaTransaccion       DATE          NULL,
        FechaUltimoPago              DATE          NULL,
        MontoUltimoPago              DECIMAL(15,2) NULL,
        CodigoRetencion              NVARCHAR(1)   NULL,
        FechaCreacion                DATE          NULL,
        FechaEntradaSistema          DATE          NULL,
        HoraEntradaSistema           TIME(0)       NULL,
        UsuarioEntradaSistema        NVARCHAR(10)  NULL,
        FechaUltimaModificacion      DATE          NULL,
        HoraUltimaModificacion       TIME(0)       NULL,
        UsuarioUltimaModificacion    NVARCHAR(10)  NULL,
        EsVigente                    BIT           NOT NULL CONSTRAINT DF_dw_dimCliente_EsVigente DEFAULT (1),
        HashDiff                     BINARY(32)    NOT NULL,
        FechaCargaDw                 DATETIME2(7)  NOT NULL CONSTRAINT DF_dw_dimCliente_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId                        INT           NULL,
        CONSTRAINT UQ_dw_dimCliente_CodigoCliente UNIQUE (CodigoCliente)
    );
END
GO

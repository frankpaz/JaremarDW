-- 114: dw.dimProveedor -- dimension Gold (SCD Tipo 1), a partir de
-- [int].dimProveedor. Nombres de negocio segun diccionario de campos real
-- de AVM (2026-09-22, via db/discovery/discover_columnas.py).
-- VMBANK y VMBNKC comparten la misma descripcion de origen ("Bank Code") --
-- se mantienen distinguidos como CodigoBanco/CodigoBancoDetalle sin mas
-- confirmacion sobre en que se diferencian realmente.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'dimProveedor'
)
BEGIN
    CREATE TABLE dw.dimProveedor (
        ProveedorKey                 INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_dimProveedor PRIMARY KEY,
        CodigoProveedor              DECIMAL(8,0)  NOT NULL,
        NombreProveedor              NVARCHAR(50)  NULL,
        ClaveBusqueda                NVARCHAR(10)  NULL,
        Direccion1                   NVARCHAR(50)  NULL,
        Direccion2                   NVARCHAR(50)  NULL,
        CodigoEstado                 NVARCHAR(3)   NULL,
        CodigoPais                   NVARCHAR(4)   NULL,
        TipoProveedor                NVARCHAR(4)   NULL,
        NumeroEmpresa                DECIMAL(2,0)  NULL,
        CodigoTerminos               NVARCHAR(2)   NULL,
        ProveedorPagoA               DECIMAL(8,0)  NULL,
        CodigoMoneda                 NVARCHAR(3)   NULL,
        MetodoPago                   NVARCHAR(1)   NULL,
        ProveedorUnaVez              NVARCHAR(1)   NULL,
        NombreContacto               NVARCHAR(30)  NULL,
        Telefono                     NVARCHAR(25)  NULL,
        CostoIncluyeImpuesto         NVARCHAR(1)   NULL,
        CodigoImpuesto               NVARCHAR(5)   NULL,
        NumeroIdentificacionFiscal   NVARCHAR(12)  NULL,
        TipoProveedor1099            NVARCHAR(1)   NULL,
        Codigo1099                   NVARCHAR(9)   NULL,
        FechaUltimoPago              DATE          NULL,
        PagosAnioActual              DECIMAL(15,2) NULL,
        ComprasAnioActual            DECIMAL(15,2) NULL,
        CodigoRetencion              NVARCHAR(1)   NULL,
        EstadoProveedor              NVARCHAR(1)   NULL,
        CodigoBanco                  NVARCHAR(3)   NULL,
        CodigoBancoDetalle           NVARCHAR(10)  NULL,
        SucursalBancaria             NVARCHAR(25)  NULL,
        CuentaBancaria               NVARCHAR(25)  NULL,
        Transportista                NVARCHAR(6)   NULL,
        MedioTransporte              NVARCHAR(4)   NULL,
        Idioma                       NVARCHAR(3)   NULL,
        EsVigente                    BIT           NOT NULL CONSTRAINT DF_dw_dimProveedor_EsVigente DEFAULT (1),
        HashDiff                     BINARY(32)    NOT NULL,
        FechaCargaDw                 DATETIME2(7)  NOT NULL CONSTRAINT DF_dw_dimProveedor_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId                        INT           NULL,
        CONSTRAINT UQ_dw_dimProveedor_CodigoProveedor UNIQUE (CodigoProveedor)
    );
END
GO

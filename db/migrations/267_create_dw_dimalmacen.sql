-- 267: dw.dimAlmacen -- dimension Gold (SCD Tipo 1), a partir de [int].dimAlmacen
-- (PROLX835F.IWM). Trae activos (LID 'WM') y dados de baja ('WZ'), porque clientes
-- y documentos siguen usando almacenes dados de baja:
--   EsActivo  = 1 para 'WM', 0 para 'WZ'. Para listar solo almacenes activos filtrar EsActivo = 1.
--   EsVigente = el almacen existe hoy en IWM.
-- No se cargan los acumulados de ventas/costo por mes de IWM (estan en los hechos).
-- Las banderas se guardan tal cual del origen (Y/N o 1/0). EmpresaKey/PaisKey se
-- resuelven en el merge con LEFT JOIN, sin FK: NULL si el codigo no existe en
-- dw.dimEmpresas/dw.dimPais (ej. CodigoEmpresa 0).

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'dimAlmacen'
)
BEGIN
    CREATE TABLE dw.dimAlmacen (
        AlmacenKey                  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_dimAlmacen PRIMARY KEY,
        CodigoAlmacen               NVARCHAR(3)    NOT NULL,
        TipoRegistro                NVARCHAR(2)    NULL,
        EsActivo                    BIT            NOT NULL CONSTRAINT DF_dw_dimAlmacen_EsActivo DEFAULT (1),
        Descripcion                 NVARCHAR(30)   NULL,
        EmpresaKey                  INT            NULL,
        CodigoEmpresa               DECIMAL(2,0)   NULL,
        CodigoFacilidad             NVARCHAR(3)    NULL,
        Direccion1                  NVARCHAR(50)   NULL,
        Direccion2                  NVARCHAR(50)   NULL,
        Direccion3                  NVARCHAR(50)   NULL,
        PaisKey                     INT            NULL,
        CodigoPais                  NVARCHAR(4)    NULL,
        CodigoEstado                NVARCHAR(3)    NULL,
        CodigoPostal                NVARCHAR(9)    NULL,
        Telefono                    NVARCHAR(25)   NULL,
        Fax                         NVARCHAR(25)   NULL,
        AlmacenAsignable            NVARCHAR(1)    NULL,
        AlmacenNeteable             NVARCHAR(1)    NULL,
        CosteaMaterial              NVARCHAR(1)    NULL,
        UsaPronostico               NVARCHAR(1)    NULL,
        TipoAlmacen                 DECIMAL(1,0)   NULL,
        RequiereAsignacion          DECIMAL(1,0)   NULL,
        ToleranciaDiasMas           DECIMAL(3,0)   NULL,
        ToleranciaDiasMenos         DECIMAL(3,0)   NULL,
        ToleranciaCantidadMasPct    DECIMAL(4,1)   NULL,
        ToleranciaCantidadMenosPct  DECIMAL(4,1)   NULL,
        CierreAutomatico            NVARCHAR(1)    NULL,
        UbicacionRecepcion          NVARCHAR(10)   NULL,
        UbicacionEnvio              NVARCHAR(10)   NULL,
        Idioma                      NVARCHAR(3)    NULL,
        FechaUltimaTransaccion      DATE           NULL,
        UsuarioCreacion             NVARCHAR(10)   NULL,
        FechaCreacion               DATE           NULL,
        HoraCreacion                TIME(0)        NULL,
        UsuarioModificacion         NVARCHAR(10)   NULL,
        FechaModificacion           DATE           NULL,
        HoraModificacion            TIME(0)        NULL,
        EsVigente                   BIT            NOT NULL CONSTRAINT DF_dw_dimAlmacen_EsVigente DEFAULT (1),
        HashDiff                    BINARY(32)     NOT NULL,
        FechaCargaDw                DATETIME2(7)   NOT NULL CONSTRAINT DF_dw_dimAlmacen_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId                       INT            NULL,
        CONSTRAINT UQ_dw_dimAlmacen_CodigoAlmacen UNIQUE (CodigoAlmacen)
    );
END
GO

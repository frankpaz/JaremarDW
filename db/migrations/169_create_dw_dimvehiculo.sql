-- 169: dw.dimVehiculo -- dimension Gold (SCD Tipo 1), a partir de [int].dimVehiculo.
-- Nombres naturales segun el dato que realmente guarda cada columna (el uso
-- difiere de la descripcion del AS400 en varias):
--   CMCDES Description        -> MarcaModelo         ("MACK", "ISUZU/NPK66")
--   CMXDES Extra Description  -> Placa               ("PAD 3803")
--   CMADR1 Address Line 1     -> EmpresaPropietaria
--   CMADR2 Address Line 2     -> Observaciones       ("CON CAJA SEGURIDAD")
--   CMADR5 Address Line 5     -> NumeroIdentidad     (13 digitos, 46% poblado)
--   CMADR6 Address Line 6     -> TipoVehiculo        (CABEZAL, CAMION, FURGON...)
--   CMATTN Attention To       -> NombreMotorista
--   CMDATN E-mail Address     -> ClaseVehiculo       ("CA10", "FU23")
--   CMSHPC Std Shipment Chg.  -> Capacidad           (14000, 25000)
-- Las demas son traduccion directa de su descripcion. ProveedorKey/PaisKey se
-- resuelven en el merge con LEFT JOIN, sin FK: NULL si el codigo no existe en
-- dw.dimProveedor/dw.dimPais (ej. CodigoProveedor 99999999, CodigoPais 'SAL').

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'dimVehiculo'
)
BEGIN
    CREATE TABLE dw.dimVehiculo (
        VehiculoKey            INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_dimVehiculo PRIMARY KEY,
        CodigoVehiculo         NVARCHAR(6)    NOT NULL,
        TipoRegistro           NVARCHAR(2)    NULL,
        MarcaModelo            NVARCHAR(30)   NULL,
        Placa                  NVARCHAR(50)   NULL,
        TipoVehiculo           NVARCHAR(50)   NULL,
        ClaseVehiculo          NVARCHAR(50)   NULL,
        Capacidad              DECIMAL(15,2)  NULL,
        EmpresaPropietaria     NVARCHAR(50)   NULL,
        NumeroIdentidad        NVARCHAR(50)   NULL,
        NombreMotorista        NVARCHAR(30)   NULL,
        Telefono               NVARCHAR(25)   NULL,
        Observaciones          NVARCHAR(50)   NULL,
        ProveedorKey           INT            NULL,
        CodigoProveedor        DECIMAL(8,0)   NULL,
        PaisKey                INT            NULL,
        CodigoPais             NVARCHAR(4)    NULL,
        CodigoEstado           NVARCHAR(3)    NULL,
        CodigoPostal           NVARCHAR(10)   NULL,
        CalificacionDesempeno  DECIMAL(1,0)   NULL,
        IndicadorFacturacion   NVARCHAR(1)    NULL,
        CodigoCargoFlete       NVARCHAR(2)    NULL,
        UsuarioModificacion    NVARCHAR(10)   NULL,
        FechaModificacion      DATE           NULL,
        HoraModificacion       TIME(0)        NULL,
        EsVigente              BIT            NOT NULL CONSTRAINT DF_dw_dimVehiculo_EsVigente DEFAULT (1),
        HashDiff               BINARY(32)     NOT NULL,
        FechaCargaDw           DATETIME2(7)   NOT NULL CONSTRAINT DF_dw_dimVehiculo_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId                  INT            NULL,
        CONSTRAINT UQ_dw_dimVehiculo_CodigoVehiculo UNIQUE (CodigoVehiculo)
    );
END
GO

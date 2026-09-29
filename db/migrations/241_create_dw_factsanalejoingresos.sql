-- 241: dw.factSanAlejoIngresos -- hecho Gold del dominio SanAlejo (SCD Tipo 1: una fila = estado actual del
-- documento), a partir de [int].factSanAlejoIngresos: ingresos (recepciones) de productos en las extractoras -- sobre todo aceite crudo y fruta de
-- otras extractoras, fincas y proveedores --, con el documento y peso del envio de origen.
--
-- Llave de negocio CodigoEmpresa + NumeroDocumento. IngresoKey es estable: el MERGE nunca borra; los
-- documentos que desaparecen del AS400 quedan con EsVigente = 0.
-- Llaves de dimension (LEFT JOIN, NULL si el codigo no esta en el catalogo): EmpresaKey, SanAlejoProductoKey, SanAlejoLocalizacionKey, SanAlejoTransportistaKey, SanAlejoClienteKey.
-- Pesos en kg tal cual del origen (la descripcion del AS400 dice T.M.): PesoNeto = PesoBruto - PesoTara.
-- Hay ~1 dia de rezago: las boletas del dia viven en PIDSA.SPVTRA* hasta que se cierran.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'factSanAlejoIngresos'
)
BEGIN
    CREATE TABLE dw.factSanAlejoIngresos (
        IngresoKey                 INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_factSanAlejoIngresos PRIMARY KEY,
        EmpresaKey                 INT            NULL CONSTRAINT FK_dw_factSanAlejoIngresos_EmpresaKey REFERENCES dw.dimEmpresas(EmpresaKey),
        SanAlejoProductoKey        INT            NULL CONSTRAINT FK_dw_factSanAlejoIngresos_SanAlejoProductoKey REFERENCES dw.dimSanAlejoProducto(SanAlejoProductoKey),
        SanAlejoLocalizacionKey    INT            NULL CONSTRAINT FK_dw_factSanAlejoIngresos_SanAlejoLocalizacionKey REFERENCES dw.dimSanAlejoLocalizacion(SanAlejoLocalizacionKey),
        SanAlejoTransportistaKey   INT            NULL CONSTRAINT FK_dw_factSanAlejoIngresos_SanAlejoTransportistaKey REFERENCES dw.dimSanAlejoTransportista(SanAlejoTransportistaKey),
        SanAlejoClienteKey         INT            NULL CONSTRAINT FK_dw_factSanAlejoIngresos_SanAlejoClienteKey REFERENCES dw.dimSanAlejoCliente(SanAlejoClienteKey),
        CodigoEmpresa              INT            NOT NULL,
        NumeroDocumento            BIGINT         NOT NULL,
        CodigoSucursal             INT            NULL,
        FechaDocumento             DATE           NULL,
        HoraDocumento              TIME(0)        NULL,
        Placa                      NVARCHAR(9)    NULL,
        NombreVendedor             NVARCHAR(30)   NULL,
        CodigoCliente              INT            NULL,
        Conductor                  NVARCHAR(30)   NULL,
        CodigoProducto             NVARCHAR(5)    NULL,
        Comentario1                NVARCHAR(50)   NULL,
        Comentario2                NVARCHAR(50)   NULL,
        Comentario3                NVARCHAR(50)   NULL,
        PesoBruto                  DECIMAL(7,0)   NULL,
        PesoTara                   DECIMAL(7,0)   NULL,
        PesoNeto                   DECIMAL(7,0)   NULL,
        CodigoTransportista        INT            NULL,
        CodigoLocalizacion         INT            NULL,
        Sello1                     NVARCHAR(10)   NULL,
        Sello2                     NVARCHAR(10)   NULL,
        Sello3                     NVARCHAR(10)   NULL,
        Sello4                     NVARCHAR(10)   NULL,
        Sello5                     NVARCHAR(10)   NULL,
        Sello6                     NVARCHAR(10)   NULL,
        Sello7                     NVARCHAR(10)   NULL,
        Sello8                     NVARCHAR(10)   NULL,
        Sello9                     NVARCHAR(10)   NULL,
        Usuario                    NVARCHAR(10)   NULL,
        PorcentajeAcidez           DECIMAL(5,3)   NULL,
        PorcentajeHumedad          DECIMAL(5,3)   NULL,
        DocumentoReferencia        BIGINT         NULL,
        PesoEnvioOrigen            DECIMAL(7,0)   NULL,
        FechaEnvioOrigen           DATE           NULL,
        MarcaModificada            NVARCHAR(1)    NULL,
        UsuarioModifico            NVARCHAR(10)   NULL,
        FechaModificacion          DATE           NULL,
        NumeroControl              NVARCHAR(10)   NULL,
        FechaSalida                DATE           NULL,
        HoraSalida                 TIME(0)        NULL,
        Certificada                NVARCHAR(2)    NULL,
        ModeloCertificacion        NVARCHAR(5)    NULL,
        ProductoSustentable        NVARCHAR(2)    NULL,
        BoletaVenta                DECIMAL(20,0)  NULL,
        NumeroEnvio                BIGINT         NULL,
        FechaEnvio                 DATE           NULL,
        NumeroFactura              BIGINT         NULL,
        SemanaProceso              INT            NULL,
        PeriodoOperativo           INT            NULL,
        MesContable                INT            NULL,
        AnioContable               INT            NULL,
        PlacaCabezal               NVARCHAR(10)   NULL,
        PlacaCisterna              NVARCHAR(10)   NULL,
        CodigoMotorista            NVARCHAR(20)   NULL,
        CodigoTransportistaTexto   NVARCHAR(10)   NULL,
        CampoTexto1                NVARCHAR(20)   NULL,
        CampoTexto3                NVARCHAR(20)   NULL,
        CampoTexto5                NVARCHAR(20)   NULL,
        CampoNumerico1             DECIMAL(15,2)  NULL,
        CampoNumerico2             DECIMAL(15,2)  NULL,
        CampoNumerico6             DECIMAL(15,0)  NULL,
        CampoNumerico7             DECIMAL(15,0)  NULL,
        HoraBruto                  TIME(0)        NULL,
        HoraTara                   TIME(0)        NULL,
        FechaTara                  DATE           NULL,
        FechaBruto                 DATE           NULL,
        IdEntrada                  BIGINT         NULL,
        IdSalida                   BIGINT         NULL,
        ContarRacimos              NVARCHAR(1)    NULL,
        ControlarCalidad           NVARCHAR(1)    NULL,
        Repeticiones               INT            NOT NULL,
        EsVigente                  BIT            NOT NULL CONSTRAINT DF_dw_factSanAlejoIngresos_EsVigente DEFAULT (1),
        HashDiff                   BINARY(32)     NOT NULL,
        FechaAlta                  DATETIME2(7)   NOT NULL,
        FechaUltimoCambio          DATETIME2(7)   NULL,
        FechaCargaDw               DATETIME2(7)   NOT NULL CONSTRAINT DF_dw_factSanAlejoIngresos_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId                      INT            NULL,
        CONSTRAINT UQ_dw_factSanAlejoIngresos_Documento UNIQUE (CodigoEmpresa, NumeroDocumento)
    );
    CREATE INDEX IX_dw_factSanAlejoIngresos_FechaDocumento ON dw.factSanAlejoIngresos (FechaDocumento);
END
GO

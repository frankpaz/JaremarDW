-- 205: dw.factBasculaBufalo -- hecho Gold de boletas de bascula (SCD Tipo 1: una fila = estado actual
-- de la boleta), a partir de [int].factBasculaBufalo. Nombres de negocio.
--
-- Llave de negocio: CodigoBascula + NumeroBoleta + FechaGeneracion + HoraGeneracionOrigen (la
-- construida en 203; HoraGeneracionOrigen es el entero del AS400 y HoraGeneracion su TIME).
-- BoletaKey es estable: el MERGE nunca borra; las boletas que desaparecen del AS400 quedan con
-- EsVigente = 0.
-- Llaves de dimension (LEFT JOIN, NULL si el codigo no existe en el catalogo): BasculaKey,
-- TipoBoletaKey, ProductoBasculaKey (~15 % de los codigos de producto no estan en BASPRODU),
-- LugarOrigenKey (ORIGEN) y LugarDestinoKey (NUMLUGAR) contra dw.dimLugarBascula.
-- CodigoProveedorBascula (NUMPROV) queda sin dimension: mezcla codigos de BASPROVE y de
-- BASLUGAR (solo ~17 % esta en BASPROVE). NumeroEnvio cruza con dw.factEnvios.NumeroEnvio.
-- Los pesos van tal cual del origen: PesoNeto = PesoBruto - PesoTara y sale NEGATIVO en las
-- entradas de materia prima (tipos 1 y 5), donde la primera pesada es la del camion cargado.
-- EstatusBoleta 'T' = solo tara (boleta abierta), 'B' = con bruto.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'factBasculaBufalo'
)
BEGIN
    CREATE TABLE dw.factBasculaBufalo (
        BoletaKey                INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_factBasculaBufalo PRIMARY KEY,
        BasculaKey               INT            NULL CONSTRAINT FK_dw_factBasculaBufalo_BasculaKey REFERENCES dw.dimBascula(BasculaKey),
        TipoBoletaKey            INT            NULL CONSTRAINT FK_dw_factBasculaBufalo_TipoBoletaKey REFERENCES dw.dimTipoBoleta(TipoBoletaKey),
        ProductoBasculaKey       INT            NULL CONSTRAINT FK_dw_factBasculaBufalo_ProductoBasculaKey REFERENCES dw.dimProductoBascula(ProductoBasculaKey),
        LugarOrigenKey           INT            NULL CONSTRAINT FK_dw_factBasculaBufalo_LugarOrigenKey REFERENCES dw.dimLugarBascula(LugarBasculaKey),
        LugarDestinoKey          INT            NULL CONSTRAINT FK_dw_factBasculaBufalo_LugarDestinoKey REFERENCES dw.dimLugarBascula(LugarBasculaKey),
        CodigoBascula            INT            NOT NULL,
        NumeroBoleta             INT            NOT NULL,
        FechaGeneracion          DATE           NOT NULL,
        HoraGeneracionOrigen     INT            NOT NULL,
        HoraGeneracion           TIME(0)        NULL,
        CodigoUsuarioBascula     INT            NULL,
        NumeroEnvio              INT            NULL,
        CodigoTipoBoleta         INT            NULL,
        NumeroPlaca              NVARCHAR(10)   NULL,
        NombreMotorista          NVARCHAR(40)   NULL,
        CodigoLugarOrigen        INT            NULL,
        CodigoLugarDestino       INT            NULL,
        PesoManifiesto           DECIMAL(15,0)  NULL,
        PesoTara                 DECIMAL(15,0)  NULL,
        FechaTara                DATE           NULL,
        HoraTara                 TIME(0)        NULL,
        PesoBruto                DECIMAL(15,0)  NULL,
        FechaBruto               DATE           NULL,
        HoraBruto                TIME(0)        NULL,
        PesoNeto                 DECIMAL(15,0)  NULL,
        DiferenciaPeso           DECIMAL(15,0)  NULL,
        Reimpreso                NVARCHAR(1)    NULL,
        EstatusBoleta            NVARCHAR(1)    NULL,
        CodigoProductoBascula    INT            NULL,
        CodigoProveedorBascula   INT            NULL,
        Marchamos                NVARCHAR(60)   NULL,
        Observaciones            NVARCHAR(60)   NULL,
        NumerosDocumentos        NVARCHAR(60)   NULL,
        PesoAprobadoAuditoria    DECIMAL(15,0)  NULL,
        AuditorAutorizo          NVARCHAR(30)   NULL,
        BasculaTara1             NVARCHAR(35)   NULL,
        BasculaTara2             NVARCHAR(35)   NULL,
        BasculaTara3             NVARCHAR(35)   NULL,
        BasculaBruto1            NVARCHAR(35)   NULL,
        BasculaBruto2            NVARCHAR(35)   NULL,
        BasculaBruto3            NVARCHAR(35)   NULL,
        FechaTara1               DATE           NULL,
        HoraTara1                TIME(0)        NULL,
        PesoTara1                DECIMAL(15,0)  NULL,
        FechaTara2               DATE           NULL,
        HoraTara2                TIME(0)        NULL,
        PesoTara2                DECIMAL(15,0)  NULL,
        FechaTara3               DATE           NULL,
        HoraTara3                TIME(0)        NULL,
        PesoTara3                DECIMAL(15,0)  NULL,
        FechaBruto1              DATE           NULL,
        HoraBruto1               TIME(0)        NULL,
        PesoBruto1               DECIMAL(15,0)  NULL,
        FechaBruto2              DATE           NULL,
        HoraBruto2               TIME(0)        NULL,
        PesoBruto2               DECIMAL(15,0)  NULL,
        FechaBruto3              DATE           NULL,
        HoraBruto3               TIME(0)        NULL,
        PesoBruto3               DECIMAL(15,0)  NULL,
        PesoManifiesto1          DECIMAL(15,0)  NULL,
        PesoManifiesto2          DECIMAL(15,0)  NULL,
        PesoManifiesto3          DECIMAL(15,0)  NULL,
        PesoNeto1                DECIMAL(15,0)  NULL,
        PesoNeto2                DECIMAL(15,0)  NULL,
        PesoNeto3                DECIMAL(15,0)  NULL,
        DiferenciaPeso1          DECIMAL(15,0)  NULL,
        DiferenciaPeso2          DECIMAL(15,0)  NULL,
        DiferenciaPeso3          DECIMAL(15,0)  NULL,
        MarcaCamion              NVARCHAR(30)   NULL,
        ColorCamion              NVARCHAR(30)   NULL,
        NumeroDocumentoOrigen    NVARCHAR(10)   NULL,
        FechaDocumentoOrigen     DATE           NULL,
        Estatus1                 NVARCHAR(1)    NULL,
        Estatus2                 NVARCHAR(1)    NULL,
        NombreOperador           NVARCHAR(40)   NULL,
        ModoConexion             NVARCHAR(30)   NULL,
        IdentificadorEntrada     NVARCHAR(15)   NULL,
        IdentificadorSalida      NVARCHAR(15)   NULL,
        Repeticiones             INT            NOT NULL,
        EsVigente                BIT            NOT NULL CONSTRAINT DF_dw_factBasculaBufalo_EsVigente DEFAULT (1),
        HashDiff                 BINARY(32)     NOT NULL,
        FechaAlta                DATETIME2(7)   NOT NULL,
        FechaUltimoCambio        DATETIME2(7)   NULL,
        FechaCargaDw             DATETIME2(7)   NOT NULL CONSTRAINT DF_dw_factBasculaBufalo_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId                    INT            NULL,
        CONSTRAINT UQ_dw_factBasculaBufalo_Boleta UNIQUE (CodigoBascula, NumeroBoleta, FechaGeneracion, HoraGeneracionOrigen)
    );
    CREATE INDEX IX_dw_factBasculaBufalo_FechaGeneracion ON dw.factBasculaBufalo (FechaGeneracion);
    CREATE INDEX IX_dw_factBasculaBufalo_NumeroEnvio ON dw.factBasculaBufalo (NumeroEnvio);
END
GO

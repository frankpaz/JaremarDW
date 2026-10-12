-- 272: dw.dimUbicacion -- dimension Gold (SCD Tipo 1), a partir de [int].dimUbicacion
-- (PROLX835F.ILM). Una fila por ubicacion dentro de un almacen (CodigoAlmacen +
-- CodigoUbicacion). Trae activas (WID 'WL') y dadas de baja ('WZ'):
--   EsActivo  = 1 para 'WL', 0 para 'WZ'. Para listar solo ubicaciones activas filtrar EsActivo = 1.
--   EsVigente = la ubicacion existe hoy en ILM.
-- AlmacenKey se resuelve en el merge con LEFT JOIN (todas las ubicaciones tienen su
-- almacen en IWM). CodigoCentroBeneficio (LMPRF, "Profit Center") se guarda como codigo:
-- solo el ~78 % coincide con dw.dimCentroCosto, asi que no se resuelve como llave.
-- Las banderas se guardan tal cual del origen.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'dimUbicacion'
)
BEGIN
    CREATE TABLE dw.dimUbicacion (
        UbicacionKey                INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_dimUbicacion PRIMARY KEY,
        CodigoAlmacen               NVARCHAR(3)    NOT NULL,
        CodigoUbicacion             NVARCHAR(10)   NOT NULL,
        AlmacenKey                  INT            NULL
            CONSTRAINT FK_dw_dimUbicacion_dimAlmacen REFERENCES dw.dimAlmacen(AlmacenKey),
        TipoRegistro                NVARCHAR(2)    NULL,
        EsActivo                    BIT            NOT NULL CONSTRAINT DF_dw_dimUbicacion_EsActivo DEFAULT (1),
        Descripcion                 NVARCHAR(30)   NULL,
        CodigoCentroBeneficio       NVARCHAR(10)   NULL,
        TipoUbicacion               NVARCHAR(1)    NULL,
        Zona                        NVARCHAR(3)    NULL,
        DiasConteoCiclico           DECIMAL(3,0)   NULL,
        MaximoTarimas               DECIMAL(11,2)  NULL,
        UbicacionAsignable          NVARCHAR(1)    NULL,
        UbicacionForzadaDefecto     NVARCHAR(1)    NULL,
        EsVigente                   BIT            NOT NULL CONSTRAINT DF_dw_dimUbicacion_EsVigente DEFAULT (1),
        HashDiff                    BINARY(32)     NOT NULL,
        FechaCargaDw                DATETIME2(7)   NOT NULL CONSTRAINT DF_dw_dimUbicacion_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId                       INT            NULL,
        CONSTRAINT UQ_dw_dimUbicacion_AlmacenUbicacion UNIQUE (CodigoAlmacen, CodigoUbicacion)
    );
END
GO

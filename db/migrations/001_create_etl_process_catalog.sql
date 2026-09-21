-- 001: catálogo de procesos ETL (dbo.EtlProcess)
-- v3: punto de partida limpio. Producto y Bascula (sembrados en v1/v2) fueron
-- descontinuados el 2026-09-21 -- el usuario eliminó manualmente
-- stg.dimProducto y stg.factMovimientosBascula por no servirle. El catálogo
-- arranca vacío; se puebla vía dbo.usp_Etl_ProcesoRegistrar según se vayan
-- incorporando procesos reales.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dbo' AND t.name = 'EtlProcess'
)
BEGIN
    CREATE TABLE dbo.EtlProcess (
        ProcesoId          INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_EtlProcess PRIMARY KEY,
        ProcesoNombre       VARCHAR(50)   NOT NULL,
        Dominio             VARCHAR(30)   NOT NULL CONSTRAINT DF_EtlProcess_Dominio DEFAULT ('SinClasificar'),
        SistemaOrigen       VARCHAR(50)   NULL,
        EsquemaOrigen       VARCHAR(20)   NULL,
        TablaOrigen         VARCHAR(128)  NULL,
        EsquemaDestino      VARCHAR(20)   NULL,
        TablaDestino        VARCHAR(128)  NULL,
        TipoCarga           VARCHAR(20)   NOT NULL CONSTRAINT DF_EtlProcess_TipoCarga DEFAULT ('Incremental'),
        Activo              BIT           NOT NULL CONSTRAINT DF_EtlProcess_Activo DEFAULT (1),
        FechaCreacion       DATETIME2(7)  NOT NULL CONSTRAINT DF_EtlProcess_FechaCreacion DEFAULT (SYSDATETIME()),
        FechaModificacion   DATETIME2(7)  NULL,
        CONSTRAINT UQ_EtlProcess_ProcesoNombre UNIQUE (ProcesoNombre),
        CONSTRAINT CK_EtlProcess_TipoCarga CHECK (TipoCarga IN ('Incremental','FULL'))
    );
END
GO

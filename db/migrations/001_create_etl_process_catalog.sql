-- 001: catálogo de procesos ETL (dbo.EtlProcess)
-- v2: dbo/dw se resetearon a un espejo limpio de producción (sin datos, sin objetos
-- de control). Ya no existe ningún proceso que dependa de nombres/columnas viejas
-- (dw.usp_MergeBascula / usp_MergeProducto tampoco existen ya), así que el diseño
-- de aquí en adelante es limpio, no aditivo sobre estructuras heredadas.

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

-- Semilla: procesos no-solares conocidos hoy en JAREMAR (producto y báscula).
-- factMovimientosBascula reemplazó a factBascula en el rebuild de stg del 2026-09-20.
IF NOT EXISTS (SELECT 1 FROM dbo.EtlProcess WHERE ProcesoNombre = 'Producto')
    INSERT INTO dbo.EtlProcess (ProcesoNombre, Dominio, SistemaOrigen, EsquemaOrigen, TablaOrigen, EsquemaDestino, TablaDestino, TipoCarga)
    VALUES ('Producto', 'Producto', 'AS400/LX', 'stg', 'dimProducto', 'dw', 'dimProducto', 'FULL');
GO

IF NOT EXISTS (SELECT 1 FROM dbo.EtlProcess WHERE ProcesoNombre = 'Bascula')
    INSERT INTO dbo.EtlProcess (ProcesoNombre, Dominio, SistemaOrigen, EsquemaOrigen, TablaOrigen, EsquemaDestino, TablaDestino, TipoCarga)
    VALUES ('Bascula', 'Bascula', 'AS400/LX', 'stg', 'factMovimientosBascula', 'dw', 'factMovimientosBascula', 'Incremental');
GO

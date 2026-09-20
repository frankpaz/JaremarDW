-- 001: catálogo de procesos ETL (dbo.EtlProcess)
-- Aditivo puro: no toca ETL_Control ni ETL_Log. Backfillea con lo que ya existe hoy.

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
        CONSTRAINT UQ_EtlProcess_ProcesoNombre UNIQUE (ProcesoNombre)
    );
END
GO

-- Backfill: cualquier Proceso ya usado en ETL_Control o ETL_Log entra al catálogo
INSERT INTO dbo.EtlProcess (ProcesoNombre)
SELECT DISTINCT c.Proceso
FROM dbo.ETL_Control c
WHERE NOT EXISTS (SELECT 1 FROM dbo.EtlProcess p WHERE p.ProcesoNombre = c.Proceso);
GO

INSERT INTO dbo.EtlProcess (ProcesoNombre)
SELECT DISTINCT l.Proceso
FROM dbo.ETL_Log l
WHERE NOT EXISTS (SELECT 1 FROM dbo.EtlProcess p WHERE p.ProcesoNombre = l.Proceso);
GO

-- Clasificación conocida hoy (no-solar): Producto y Bascula ya tienen MERGE en dw
UPDATE dbo.EtlProcess
SET Dominio = 'Producto', SistemaOrigen = 'AS400/LX', EsquemaOrigen = 'stg', TablaOrigen = 'dimProducto',
    EsquemaDestino = 'dw', TablaDestino = 'dimProducto'
WHERE ProcesoNombre = 'Producto';
GO

IF NOT EXISTS (SELECT 1 FROM dbo.EtlProcess WHERE ProcesoNombre = 'Bascula')
    INSERT INTO dbo.EtlProcess (ProcesoNombre, Dominio, SistemaOrigen, EsquemaOrigen, TablaOrigen, EsquemaDestino, TablaDestino, TipoCarga)
    VALUES ('Bascula', 'Bascula', 'AS400/LX', 'stg', 'factBascula', 'dw', 'factBascula', 'Incremental');
ELSE
    UPDATE dbo.EtlProcess
    SET Dominio = 'Bascula', SistemaOrigen = 'AS400/LX', EsquemaOrigen = 'stg', TablaOrigen = 'factBascula',
        EsquemaDestino = 'dw', TablaDestino = 'factBascula'
    WHERE ProcesoNombre = 'Bascula';
GO

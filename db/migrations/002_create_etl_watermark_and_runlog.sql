-- 002: watermark y log de ejecución del framework ETL
-- v2: diseño limpio (dbo.EtlWatermark / dbo.EtlRunLog) en vez de extender
-- ETL_Control/ETL_Log heredadas -- esas tablas ya no existen tras el reset del
-- ambiente y ningún proceso vivo depende de su nombre o columnas.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dbo' AND t.name = 'EtlWatermark'
)
BEGIN
    CREATE TABLE dbo.EtlWatermark (
        ProcesoId               INT NOT NULL CONSTRAINT PK_EtlWatermark PRIMARY KEY,
        UltimaCargaFechaHora    DATETIME2(7) NULL,
        TipoCarga               VARCHAR(20)  NOT NULL CONSTRAINT DF_EtlWatermark_TipoCarga DEFAULT ('Incremental'),
        FechaActualizacion      DATETIME2(7) NOT NULL CONSTRAINT DF_EtlWatermark_FechaActualizacion DEFAULT (SYSDATETIME()),
        CONSTRAINT FK_EtlWatermark_EtlProcess FOREIGN KEY (ProcesoId) REFERENCES dbo.EtlProcess(ProcesoId)
    );
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dbo' AND t.name = 'EtlRunLog'
)
BEGIN
    CREATE TABLE dbo.EtlRunLog (
        RunId               INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_EtlRunLog PRIMARY KEY,
        ProcesoId           INT NOT NULL,
        FechaInicio         DATETIME2(7) NOT NULL CONSTRAINT DF_EtlRunLog_FechaInicio DEFAULT (SYSDATETIME()),
        FechaFin            DATETIME2(7) NULL,
        Estado              VARCHAR(20)  NOT NULL CONSTRAINT DF_EtlRunLog_Estado DEFAULT ('EN PROCESO'),
        FilasLeidas         INT NULL,
        FilasInsertadas     INT NULL,
        FilasActualizadas   INT NULL,
        FilasIgnoradas      INT NULL,
        FilasRechazadas     INT NULL,
        Descuadre           INT NULL,
        MensajeError        NVARCHAR(MAX) NULL,
        TareaError          VARCHAR(200) NULL,
        DuracionSegundos    AS (DATEDIFF(SECOND, FechaInicio, FechaFin)) PERSISTED,
        CONSTRAINT FK_EtlRunLog_EtlProcess FOREIGN KEY (ProcesoId) REFERENCES dbo.EtlProcess(ProcesoId),
        CONSTRAINT CK_EtlRunLog_Estado CHECK (Estado IN ('EN PROCESO','EXITO','ERROR','ADVERTENCIA'))
    );
    CREATE INDEX IX_EtlRunLog_ProcesoId_FechaInicio ON dbo.EtlRunLog(ProcesoId, FechaInicio DESC);
END
GO

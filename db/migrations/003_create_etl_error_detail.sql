-- 003: captura de errores a nivel de fila (hoy se pierden -- solo queda el conteo agregado
-- FilasRechazadas en ETL_Log, sin detalle de qué falló). Tabla nueva, sin impacto en lo existente.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dbo' AND t.name = 'EtlErrorDetail'
)
BEGIN
    CREATE TABLE dbo.EtlErrorDetail (
        ErrorId         BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_EtlErrorDetail PRIMARY KEY,
        LogID           INT NOT NULL,
        ProcesoId       INT NULL,
        FechaError      DATETIME2(7) NOT NULL CONSTRAINT DF_EtlErrorDetail_Fecha DEFAULT (SYSDATETIME()),
        LlaveNegocio    NVARCHAR(200) NULL,
        Payload         NVARCHAR(MAX) NULL,
        MensajeError    NVARCHAR(MAX) NULL,
        CONSTRAINT FK_EtlErrorDetail_EtlLog FOREIGN KEY (LogID) REFERENCES dbo.ETL_Log(LogID),
        CONSTRAINT FK_EtlErrorDetail_EtlProcess FOREIGN KEY (ProcesoId) REFERENCES dbo.EtlProcess(ProcesoId)
    );
    CREATE INDEX IX_EtlErrorDetail_LogID ON dbo.EtlErrorDetail(LogID);
END
GO

-- 004: procedimientos del framework de control ETL (dominio no-solar)

CREATE OR ALTER PROCEDURE dbo.usp_Etl_ProcesoRegistrar
    @Proceso        VARCHAR(50),
    @Dominio        VARCHAR(30)  = NULL,
    @SistemaOrigen  VARCHAR(50)  = NULL,
    @EsquemaOrigen  VARCHAR(20)  = NULL,
    @TablaOrigen    VARCHAR(128) = NULL,
    @EsquemaDestino VARCHAR(20)  = NULL,
    @TablaDestino   VARCHAR(128) = NULL,
    @TipoCarga      VARCHAR(20)  = NULL,
    @ProcesoId      INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    MERGE dbo.EtlProcess AS destino
    USING (SELECT @Proceso AS ProcesoNombre) AS origen
        ON destino.ProcesoNombre = origen.ProcesoNombre
    WHEN MATCHED THEN
        UPDATE SET
            Dominio           = COALESCE(@Dominio, destino.Dominio),
            SistemaOrigen     = COALESCE(@SistemaOrigen, destino.SistemaOrigen),
            EsquemaOrigen     = COALESCE(@EsquemaOrigen, destino.EsquemaOrigen),
            TablaOrigen       = COALESCE(@TablaOrigen, destino.TablaOrigen),
            EsquemaDestino    = COALESCE(@EsquemaDestino, destino.EsquemaDestino),
            TablaDestino      = COALESCE(@TablaDestino, destino.TablaDestino),
            TipoCarga         = COALESCE(@TipoCarga, destino.TipoCarga),
            FechaModificacion = SYSDATETIME()
    WHEN NOT MATCHED THEN
        INSERT (ProcesoNombre, Dominio, SistemaOrigen, EsquemaOrigen, TablaOrigen, EsquemaDestino, TablaDestino, TipoCarga)
        VALUES (@Proceso, COALESCE(@Dominio, 'SinClasificar'), @SistemaOrigen, @EsquemaOrigen, @TablaOrigen,
                @EsquemaDestino, @TablaDestino, COALESCE(@TipoCarga, 'Incremental'));

    SELECT @ProcesoId = ProcesoId FROM dbo.EtlProcess WHERE ProcesoNombre = @Proceso;
END
GO

-- Inicia una corrida: registra/actualiza el catálogo y abre la fila de log. Devuelve RunId.
CREATE OR ALTER PROCEDURE dbo.usp_Etl_RunIniciar
    @Proceso VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ProcesoId INT;
    EXEC dbo.usp_Etl_ProcesoRegistrar @Proceso = @Proceso, @ProcesoId = @ProcesoId OUTPUT;

    INSERT INTO dbo.EtlRunLog (ProcesoId, FechaInicio, Estado)
    VALUES (@ProcesoId, SYSDATETIME(), 'EN PROCESO');

    SELECT CAST(SCOPE_IDENTITY() AS INT) AS RunId;
END
GO

-- Cierra una corrida con sus contadores y estado final.
CREATE OR ALTER PROCEDURE dbo.usp_Etl_RunFinalizar
    @RunId             INT,
    @Estado            VARCHAR(20),           -- 'EXITO' | 'ERROR' | 'ADVERTENCIA'
    @FilasLeidas       INT           = NULL,
    @FilasInsertadas   INT           = NULL,
    @FilasActualizadas INT           = NULL,
    @FilasIgnoradas    INT           = NULL,
    @FilasRechazadas   INT           = NULL,
    @Descuadre         INT           = NULL,
    @MensajeError      NVARCHAR(MAX) = NULL,
    @TareaError        VARCHAR(200)  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.EtlRunLog
    SET FechaFin           = SYSDATETIME(),
        Estado              = @Estado,
        FilasLeidas         = COALESCE(@FilasLeidas, FilasLeidas),
        FilasInsertadas     = COALESCE(@FilasInsertadas, FilasInsertadas),
        FilasActualizadas   = COALESCE(@FilasActualizadas, FilasActualizadas),
        FilasIgnoradas      = COALESCE(@FilasIgnoradas, FilasIgnoradas),
        FilasRechazadas     = COALESCE(@FilasRechazadas, FilasRechazadas),
        Descuadre           = COALESCE(@Descuadre, Descuadre),
        MensajeError        = COALESCE(@MensajeError, MensajeError),
        TareaError          = COALESCE(@TareaError, TareaError)
    WHERE RunId = @RunId;
END
GO

-- Lee el watermark actual de un proceso.
CREATE OR ALTER PROCEDURE dbo.usp_Etl_WatermarkObtener
    @Proceso VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.ProcesoNombre, w.UltimaCargaFechaHora, w.TipoCarga, w.FechaActualizacion
    FROM dbo.EtlProcess p
    LEFT JOIN dbo.EtlWatermark w ON w.ProcesoId = p.ProcesoId
    WHERE p.ProcesoNombre = @Proceso;
END
GO

-- Upsert del watermark tras una carga exitosa.
CREATE OR ALTER PROCEDURE dbo.usp_Etl_WatermarkActualizar
    @Proceso            VARCHAR(50),
    @NuevaFechaHora     DATETIME2(7) = NULL,
    @TipoCarga          VARCHAR(20)  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ProcesoId INT;
    EXEC dbo.usp_Etl_ProcesoRegistrar @Proceso = @Proceso, @TipoCarga = @TipoCarga, @ProcesoId = @ProcesoId OUTPUT;

    MERGE dbo.EtlWatermark AS destino
    USING (SELECT @ProcesoId AS ProcesoId) AS origen
        ON destino.ProcesoId = origen.ProcesoId
    WHEN MATCHED THEN
        UPDATE SET
            UltimaCargaFechaHora = COALESCE(@NuevaFechaHora, destino.UltimaCargaFechaHora),
            TipoCarga            = COALESCE(@TipoCarga, destino.TipoCarga),
            FechaActualizacion   = SYSDATETIME()
    WHEN NOT MATCHED THEN
        INSERT (ProcesoId, UltimaCargaFechaHora, TipoCarga)
        VALUES (@ProcesoId, @NuevaFechaHora, COALESCE(@TipoCarga, 'Incremental'));
END
GO

-- Detalle de una fila rechazada durante una corrida.
CREATE OR ALTER PROCEDURE dbo.usp_Etl_ErrorRegistrar
    @RunId        INT,
    @LlaveNegocio NVARCHAR(200) = NULL,
    @Payload      NVARCHAR(MAX) = NULL,
    @MensajeError NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ProcesoId INT = (SELECT ProcesoId FROM dbo.EtlRunLog WHERE RunId = @RunId);
    INSERT INTO dbo.EtlErrorDetail (RunId, ProcesoId, LlaveNegocio, Payload, MensajeError)
    VALUES (@RunId, @ProcesoId, @LlaveNegocio, @Payload, @MensajeError);
END
GO

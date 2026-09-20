-- 004: procedimientos del framework de control.
-- usp_ETL_LogFinalizar NO se toca (firma y cuerpo idénticos) porque dw.usp_MergeBascula
-- y dw.usp_MergeProducto dependen de su contrato; el resto se actualiza o se crea nuevo.

-- Alta/actualización idempotente en el catálogo (usado por los otros procs)
CREATE OR ALTER PROCEDURE dbo.usp_ETL_ProcesoRegistrar
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

-- LogInicio: mismo contrato de siempre (@Proceso in, LogID out), ahora también
-- registra/actualiza el catálogo y guarda ProcesoId en la fila del log.
CREATE OR ALTER PROCEDURE dbo.usp_ETL_LogInicio
    @Proceso VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ProcesoId INT;
    EXEC dbo.usp_ETL_ProcesoRegistrar @Proceso = @Proceso, @ProcesoId = @ProcesoId OUTPUT;

    INSERT INTO dbo.ETL_Log (Proceso, ProcesoId, FechaInicio, Estado)
    VALUES (@Proceso, @ProcesoId, GETDATE(), 'EN PROCESO');

    SELECT CAST(SCOPE_IDENTITY() AS INT) AS LogID;
END
GO

-- ActualizarWatermark: antes solo hacía UPDATE (asumía que la fila ya existía);
-- ahora hace upsert real y también registra el proceso en el catálogo.
CREATE OR ALTER PROCEDURE dbo.usp_ETL_ActualizarWatermark
    @Proceso         VARCHAR(50),
    @NuevaFechaHora  DATETIME2(7) = NULL,
    @NuevaFechaTexto VARCHAR(10)  = NULL,
    @NuevaHoraTexto  VARCHAR(10)  = NULL,
    @TipoCarga       VARCHAR(20)  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ProcesoId INT;
    EXEC dbo.usp_ETL_ProcesoRegistrar @Proceso = @Proceso, @TipoCarga = @TipoCarga, @ProcesoId = @ProcesoId OUTPUT;

    MERGE dbo.ETL_Control AS destino
    USING (SELECT @Proceso AS Proceso) AS origen
        ON destino.Proceso = origen.Proceso
    WHEN MATCHED THEN
        UPDATE SET
            UltimaFechaHoraCarga = COALESCE(@NuevaFechaHora, destino.UltimaFechaHoraCarga),
            UltimaFechaCarga     = COALESCE(@NuevaFechaTexto, destino.UltimaFechaCarga),
            UltimaHoraCarga      = COALESCE(@NuevaHoraTexto, destino.UltimaHoraCarga),
            TipoCarga            = COALESCE(@TipoCarga, destino.TipoCarga),
            FechaEjecucion       = GETDATE(),
            ProcesoId            = @ProcesoId
    WHEN NOT MATCHED THEN
        INSERT (Proceso, ProcesoId, UltimaFechaHoraCarga, UltimaFechaCarga, UltimaHoraCarga, FechaEjecucion, TipoCarga)
        VALUES (@Proceso, @ProcesoId, @NuevaFechaHora, @NuevaFechaTexto, @NuevaHoraTexto, GETDATE(), COALESCE(@TipoCarga, 'Incremental'));
END
GO

-- Lectura del watermark (hoy no existía como proc -- se asumía SELECT directo a la tabla)
CREATE OR ALTER PROCEDURE dbo.usp_ETL_WatermarkObtener
    @Proceso VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT Proceso, UltimaFechaHoraCarga, UltimaFechaCarga, UltimaHoraCarga, TipoCarga, FechaEjecucion
    FROM dbo.ETL_Control
    WHERE Proceso = @Proceso;
END
GO

-- Detalle de filas rechazadas (nuevo -- antes ese detalle no se guardaba en ningún lado)
CREATE OR ALTER PROCEDURE dbo.usp_ETL_LogError
    @LogID        INT,
    @LlaveNegocio NVARCHAR(200) = NULL,
    @Payload      NVARCHAR(MAX) = NULL,
    @MensajeError NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ProcesoId INT = (SELECT ProcesoId FROM dbo.ETL_Log WHERE LogID = @LogID);
    INSERT INTO dbo.EtlErrorDetail (LogID, ProcesoId, LlaveNegocio, Payload, MensajeError)
    VALUES (@LogID, @ProcesoId, @LlaveNegocio, @Payload, @MensajeError);
END
GO

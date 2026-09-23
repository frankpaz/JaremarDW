-- 140: dbo.usp_Etl_AlertasObtener -- detecta corridas del framework ETL que
-- requieren atencion. Lo consume db/monitor_etl.py, que reporta y notifica.
--
-- Severidad CRITICA:
--   ERROR       corrida en ERROR dentro de la ventana, sin ninguna corrida
--               exitosa posterior del mismo proceso (un error ya superado por
--               una corrida buena no alerta).
--   COLGADA     corrida 'EN PROCESO' desde hace mas de @HorasEnProceso horas.
--   SIN_EXITO   (solo si @HorasSinExito no es NULL) proceso cuyo ultimo exito
--               tiene mas de @HorasSinExito horas.
-- Severidad ADVERTENCIA:
--   RECHAZOS    corrida con filas rechazadas dentro de la ventana.
--   DESCUADRE   corrida con Descuadre <> 0 dentro de la ventana.

CREATE OR ALTER PROCEDURE dbo.usp_Etl_AlertasObtener
    @HorasVentana    INT = 24,
    @HorasEnProceso  INT = 3,
    @HorasSinExito   INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Ahora DATETIME2(7) = SYSDATETIME();
    DECLARE @Desde DATETIME2(7) = DATEADD(HOUR, -@HorasVentana, @Ahora);

    ;WITH UltimoExito AS (
        SELECT ProcesoId, MAX(FechaInicio) AS FechaUltimoExito
        FROM dbo.EtlRunLog
        WHERE Estado IN ('EXITO', 'ADVERTENCIA')
        GROUP BY ProcesoId
    )
    SELECT a.Severidad, a.Tipo, a.Proceso, a.RunId, a.FechaInicio, a.Detalle
    FROM (
        SELECT 'CRITICA' AS Severidad, 'ERROR' AS Tipo, p.ProcesoNombre AS Proceso, r.RunId, r.FechaInicio,
               LEFT(CONCAT(ISNULL(r.TareaError, ''), ': ', ISNULL(r.MensajeError, '(sin mensaje)')), 500) AS Detalle
        FROM dbo.EtlRunLog r
        JOIN dbo.EtlProcess p ON p.ProcesoId = r.ProcesoId
        LEFT JOIN UltimoExito u ON u.ProcesoId = r.ProcesoId
        WHERE r.Estado = 'ERROR' AND r.FechaInicio >= @Desde
          AND (u.FechaUltimoExito IS NULL OR u.FechaUltimoExito < r.FechaInicio)

        UNION ALL
        SELECT 'CRITICA', 'COLGADA', p.ProcesoNombre, r.RunId, r.FechaInicio,
               CONCAT('En proceso desde hace ', DATEDIFF(MINUTE, r.FechaInicio, @Ahora), ' min')
        FROM dbo.EtlRunLog r
        JOIN dbo.EtlProcess p ON p.ProcesoId = r.ProcesoId
        WHERE r.Estado = 'EN PROCESO' AND r.FechaInicio < DATEADD(HOUR, -@HorasEnProceso, @Ahora)

        UNION ALL
        SELECT 'CRITICA', 'SIN_EXITO', p.ProcesoNombre, NULL, u.FechaUltimoExito,
               CONCAT('Ultimo exito hace ', DATEDIFF(HOUR, u.FechaUltimoExito, @Ahora), ' h (limite ', @HorasSinExito, ' h)')
        FROM UltimoExito u
        JOIN dbo.EtlProcess p ON p.ProcesoId = u.ProcesoId
        WHERE @HorasSinExito IS NOT NULL AND u.FechaUltimoExito < DATEADD(HOUR, -@HorasSinExito, @Ahora)

        UNION ALL
        SELECT 'ADVERTENCIA', 'RECHAZOS', p.ProcesoNombre, r.RunId, r.FechaInicio,
               CONCAT(r.FilasRechazadas, ' filas rechazadas (ver dbo.EtlErrorDetail)')
        FROM dbo.EtlRunLog r
        JOIN dbo.EtlProcess p ON p.ProcesoId = r.ProcesoId
        WHERE r.FechaInicio >= @Desde AND ISNULL(r.FilasRechazadas, 0) > 0

        UNION ALL
        SELECT 'ADVERTENCIA', 'DESCUADRE', p.ProcesoNombre, r.RunId, r.FechaInicio,
               CONCAT('Descuadre de ', r.Descuadre, ' filas')
        FROM dbo.EtlRunLog r
        JOIN dbo.EtlProcess p ON p.ProcesoId = r.ProcesoId
        WHERE r.FechaInicio >= @Desde AND ISNULL(r.Descuadre, 0) <> 0
    ) a
    ORDER BY CASE a.Severidad WHEN 'CRITICA' THEN 0 ELSE 1 END, a.FechaInicio DESC;
END
GO

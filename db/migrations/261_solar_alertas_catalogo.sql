-- 261: dw.usp_SolarAlertasObtener -- revisa los DATOS del dominio Solar (no las corridas, que ya revisa
-- dbo.usp_Etl_AlertasObtener). Lo llama db/monitor_etl.py con --alertas-solar (run_solar.py lo activa).
-- Mismas columnas que usp_Etl_AlertasObtener; todas con Severidad ADVERTENCIA y Proceso 'SolarCatalogo':
--
--   ORIGEN_SIN_PLANTA      agrupador de un portal (planta SMA, estacion Huawei/Solis, equipo Growatt) con
--                          inversores que no esta en la hoja Origen del catalogo (ej. una estacion nueva).
--                          Un agrupador en Origen con Planta vacia esta excluido a proposito y no alerta.
--   INVERSOR_SIN_DATOS     inversor del informe cuya ultima generacion es anterior a hoy - @DiasSinDatos.
--   INVERSOR_SIN_CAPACIDAD inversor del informe sin capacidad DC (ni del portal ni de dimDeviceCapacity).
--   SERIE_REPETIDA         el mismo numero de serie en dos inversores del informe (InversorId debe ser unico).
--   PLAN_SIN_INVERSOR      equipo del plan vigente que no cruza con ningun inversor del informe: su plan
--                          no entra al informe.

CREATE OR ALTER PROCEDURE dw.usp_SolarAlertasObtener
    @DiasSinDatos INT = 2
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Ahora DATETIME2(7) = SYSDATETIME();
    DECLARE @Hoy DATE = CAST(@Ahora AS DATE);

    SELECT CAST(Provider AS VARCHAR(20)) AS Proveedor, CAST(DeviceId AS NVARCHAR(200)) AS DeviceId,
           MAX(GenerationDate) AS Ultimo
    INTO #Ultimo
    FROM dw.vwDailyGenerationSummary
    GROUP BY Provider, DeviceId;

    SELECT a.Severidad, a.Tipo, a.Proceso, a.RunId, a.FechaInicio, a.Detalle
    FROM (
        SELECT 'ADVERTENCIA' AS Severidad, 'ORIGEN_SIN_PLANTA' AS Tipo, 'SolarCatalogo' AS Proceso,
               CAST(NULL AS INT) AS RunId, @Ahora AS FechaInicio,
               CONCAT(e.Proveedor, ' ', e.CodigoOrigen, ' (', ISNULL(MAX(e.NombreOrigen), 'sin nombre'), '): ',
                      COUNT(*), ' inversor(es) sin planta; agregarlo a la hoja Origen del catalogo') AS Detalle
        FROM dw.vwSolarEquipo e
        LEFT JOIN dw.dimPlantaSolarOrigen o
               ON o.Proveedor = e.Proveedor AND o.CodigoOrigen = e.CodigoOrigen AND o.EsVigente = 1
        WHERE o.CodigoOrigen IS NULL
        GROUP BY e.Proveedor, e.CodigoOrigen

        UNION ALL
        SELECT 'ADVERTENCIA', 'INVERSOR_SIN_DATOS', 'SolarCatalogo', NULL,
               ISNULL(CAST(u.Ultimo AS DATETIME2(7)), @Ahora),
               CASE WHEN u.Ultimo IS NULL
                    THEN CONCAT(i.Planta, ' ', i.InversorId, ' (', i.Proveedor, '): nunca ha tenido generacion')
                    ELSE CONCAT(i.Planta, ' ', i.InversorId, ' (', i.Proveedor, '): sin generacion desde ',
                                CONVERT(CHAR(10), u.Ultimo, 120), ' (', DATEDIFF(DAY, u.Ultimo, @Hoy), ' dias)') END
        FROM dw.vwRptInversor i
        LEFT JOIN #Ultimo u ON u.Proveedor = i.Proveedor AND u.DeviceId = i.DeviceKey COLLATE DATABASE_DEFAULT
        WHERE i.EnReporte = 1
          AND (u.Ultimo IS NULL OR u.Ultimo < DATEADD(DAY, -@DiasSinDatos, @Hoy))

        UNION ALL
        SELECT 'ADVERTENCIA', 'INVERSOR_SIN_CAPACIDAD', 'SolarCatalogo', NULL, @Ahora,
               CONCAT(i.Planta, ' ', i.InversorId, ' (', i.Proveedor, '): sin capacidad DC en el portal ni en dimDeviceCapacity')
        FROM dw.vwRptInversor i
        WHERE i.EnReporte = 1 AND i.CapacidadDcKwp IS NULL

        UNION ALL
        SELECT 'ADVERTENCIA', 'SERIE_REPETIDA', 'SolarCatalogo', NULL, @Ahora,
               CONCAT('La serie ', i.InversorId, ' esta en ', COUNT(*), ' inversores del informe')
        FROM dw.vwRptInversor i
        GROUP BY i.InversorId
        HAVING COUNT(*) > 1

        UNION ALL
        SELECT 'ADVERTENCIA', 'PLAN_SIN_INVERSOR', 'SolarCatalogo', NULL, @Ahora,
               CONCAT(p.Planta, ' ', p.InversorId, ' (', p.Proveedor, ' ', p.Inversor,
                      '): el plan no cruza con ningun inversor del informe y no se reporta')
        FROM (SELECT DISTINCT Planta, InversorId, Proveedor, Inversor FROM dw.dimPlanGeneracion WHERE EsVigente = 1) p
        WHERE NOT EXISTS (SELECT 1 FROM dw.vwRptInversor i WHERE i.Proveedor = p.Proveedor AND i.DeviceKey = p.Inversor)
    ) a
    ORDER BY a.Tipo, a.Detalle;

    DROP TABLE #Ultimo;
END
GO

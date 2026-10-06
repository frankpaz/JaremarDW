-- 264: inversores sin produccion para el reporte diario de Solar (db/reporte_solar.py).
-- Un dia "sin produccion" es un dia sin dato O con 0 kWh: los inversores apagados que el portal sigue
-- reportando en 0 (ej. PERFECTOR 3006383105, en 0 desde el 10/09/2026) antes no alertaban.
-- Se cuenta desde el primer dato del inversor (MARGARINA empieza el 22/09/2026: lo anterior no es falla)
-- y hasta AYER (hoy siempre esta incompleto).

-- Inversores del informe que llevan @DiasSeguidosMin o mas dias seguidos sin produccion (o que nunca
-- han tenido datos). Columnas:
--   UltimaProduccion  ultimo dia con kWh > 0 (NULL = nunca)
--   UltimoDato        ultimo dia con fila, aunque sea 0 (si es reciente, el portal reporta el equipo en 0;
--                     si es igual a UltimaProduccion, dejaron de llegar datos)
--   DiasSeguidos      dias desde UltimaProduccion (o desde el primer dato) hasta ayer
--   DiasSinProduccion dias sin produccion dentro de los ultimos @DiasVentana (desde el primer dato)
CREATE OR ALTER PROCEDURE dw.usp_SolarInversoresSinProduccion
    @DiasSeguidosMin INT = 2,
    @DiasVentana     INT = 30
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Ayer  DATE = DATEADD(DAY, -1, CAST(SYSDATETIME() AS DATE));
    DECLARE @Desde DATE = DATEADD(DAY, 1 - @DiasVentana, @Ayer);

    SELECT CAST(Provider AS VARCHAR(20)) AS Proveedor, CAST(DeviceId AS NVARCHAR(200)) AS DeviceId,
           GenerationDate AS Fecha, SUM(EnergyKwh) AS Kwh
    INTO #Dia
    FROM dw.vwDailyGenerationSummary
    WHERE GenerationDate <= @Ayer
    GROUP BY Provider, DeviceId, GenerationDate;

    SELECT Proveedor, DeviceId,
           MIN(Fecha)                                                    AS PrimerDato,
           MAX(Fecha)                                                    AS UltimoDato,
           MAX(CASE WHEN Kwh > 0 THEN Fecha END)                         AS UltimaProduccion,
           COUNT(CASE WHEN Kwh > 0 AND Fecha >= @Desde THEN 1 END)       AS DiasConProduccion
    INTO #Resumen
    FROM #Dia
    GROUP BY Proveedor, DeviceId;

    SELECT x.Planta, x.InversorId, x.Proveedor, x.UltimaProduccion, x.UltimoDato, x.DiasSeguidos, x.DiasSinProduccion
    FROM (
        SELECT i.Planta,
               i.InversorId,
               i.Proveedor,
               r.UltimaProduccion,
               r.UltimoDato,
               DATEDIFF(DAY, ISNULL(r.UltimaProduccion, DATEADD(DAY, -1, r.PrimerDato)), @Ayer) AS DiasSeguidos,
               DATEDIFF(DAY, CASE WHEN r.PrimerDato > @Desde THEN r.PrimerDato ELSE @Desde END, @Ayer) + 1
                 - r.DiasConProduccion                                                       AS DiasSinProduccion
        FROM dw.vwRptInversor i
        LEFT JOIN #Resumen r ON r.Proveedor = i.Proveedor AND r.DeviceId = i.DeviceKey COLLATE DATABASE_DEFAULT
        WHERE i.EnReporte = 1
    ) x
    WHERE x.UltimoDato IS NULL OR x.DiasSeguidos >= @DiasSeguidosMin
    ORDER BY CASE WHEN x.UltimoDato IS NULL THEN 0 ELSE 1 END, x.DiasSeguidos DESC, x.Planta, x.InversorId;

    DROP TABLE #Dia;
    DROP TABLE #Resumen;
END
GO

-- dw.usp_SolarAlertasObtener: INVERSOR_SIN_DATOS mira el ultimo dia con PRODUCCION (kWh > 0), no el
-- ultimo dia con fila. Lo demas igual que la 261.
CREATE OR ALTER PROCEDURE dw.usp_SolarAlertasObtener
    @DiasSinDatos INT = 2
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Ahora DATETIME2(7) = SYSDATETIME();
    DECLARE @Hoy DATE = CAST(@Ahora AS DATE);

    SELECT CAST(Provider AS VARCHAR(20)) AS Proveedor, CAST(DeviceId AS NVARCHAR(200)) AS DeviceId,
           MAX(CASE WHEN EnergyKwh > 0 THEN GenerationDate END) AS Ultimo
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
                    THEN CONCAT(i.Planta, ' ', i.InversorId, ' (', i.Proveedor, '): nunca ha tenido produccion')
                    ELSE CONCAT(i.Planta, ' ', i.InversorId, ' (', i.Proveedor, '): sin produccion desde ',
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

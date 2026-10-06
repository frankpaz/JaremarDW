-- 260: el "Informe Ejecutivo - Solar Jaremar" deja de tener plantas e inversores escritos en las vistas
-- (CASE de la 251/252) y los toma del catalogo de plantas (258-259) y de las dimensiones de cada portal.
--
--   dw.vwSolarEquipo (nueva): un renglon por inversor de los portales, este o no en el informe.
--       SMA -> dimSmaDevices/dimSmaPlants; Huawei -> dimHuaweiDevices/dimHuaweiStations;
--       Soliscloud -> dimSoliscloudDevices/dimSoliscloudStations; Growatt (sin dimension) -> equipos del hecho.
--       DeviceKey = id que usan los hechos; CodigoOrigen = agrupador del portal que asigna la hoja Origen.
--   dw.vwRptInversor: equipos cuyo agrupador esta asignado a una planta vigente.
--       InversorId = numero de serie (decision del usuario hasta que el equipo de plantas defina nombres).
--       Capacidad = la del portal; si no la informa, dw.dimDeviceCapacity por JoinKey (Huawei tambien por
--       SourceSn = DeviceName, como hasta ahora, mientras el proceso externo no llene el JoinKey de EDIF ADMIN).
--       EnReporte = el de la planta. Columnas nuevas al final: CodigoOrigen, Serie, NombrePortal, FuenteCapacidad.
--   dw.vwRptPlanta / dw.vwRptPlantel: Orden, MeteoSite y Plantel salen de dw.dimPlantaSolar.
--   dw.vwRptPlanPlantaDia / dw.vwRptPlanInversorDia: el plan se cruza por Proveedor + Inversor (id del equipo
--       en el portal) contra vwRptInversor; la planta es la del catalogo, no el texto del Excel del plan.
--
-- Sin cambios: vwDailyGenerationSummary, vwRptInversorDia, vwRptMeteoPlantaDia, vwRptPlantaDia, las de
-- disponibilidad, fnRptInforme y fnRptRankingInversor (leen las vistas de arriba). El RDL no se toca.

CREATE OR ALTER VIEW dw.vwSolarEquipo AS
SELECT
    CAST('sma' AS varchar(20))                                     AS Proveedor,
    CAST(d.DeviceId AS nvarchar(200))                              AS DeviceKey,
    CAST(d.PlantId AS nvarchar(200))                               AS CodigoOrigen,
    CAST(p.PlantName AS nvarchar(500))                             AS NombreOrigen,
    CAST(d.Serial AS nvarchar(200))                                AS Serie,
    CAST(d.DeviceName AS nvarchar(500))                            AS NombrePortal,
    CAST(NULLIF(d.GeneratorPowerDc, 0) / 1000.0 AS decimal(12,3))  AS CapacidadDcPortalKwp,
    CAST(NULLIF(d.GeneratorPower, 0)   / 1000.0 AS decimal(12,3))  AS CapacidadAcPortalKw
FROM dw.dimSmaDevices d
JOIN dw.dimSmaPlants p ON p.PlantId = d.PlantId AND p.EsVigente = 1
WHERE d.EsVigente = 1 AND d.IsGenerator = 1

UNION ALL
SELECT
    'huawei', CAST(d.DeviceId AS nvarchar(200)), CAST(d.StationCode AS nvarchar(200)), CAST(s.StationName AS nvarchar(500)),
    CAST(d.DeviceEsn AS nvarchar(200)), CAST(d.DeviceName AS nvarchar(500)),
    d.InstalledCapacityKwp, CAST(NULL AS decimal(12,3))
FROM dw.dimHuaweiDevices d
JOIN dw.dimHuaweiStations s ON s.StationCode = d.StationCode AND s.EsVigente = 1
WHERE d.EsVigente = 1 AND d.IsGenerator = 1

UNION ALL
SELECT
    'soliscloud', CAST(d.DeviceSn AS nvarchar(200)), CAST(d.StationId AS nvarchar(200)), CAST(s.StationName AS nvarchar(500)),
    CAST(d.DeviceSn AS nvarchar(200)), CAST(d.DeviceSn AS nvarchar(500)),
    CAST(NULL AS decimal(12,3)), CAST(NULL AS decimal(12,3))
FROM dw.dimSoliscloudDevices d
JOIN dw.dimSoliscloudStations s ON s.StationId = d.StationId AND s.EsVigente = 1
WHERE d.EsVigente = 1 AND d.IsGenerator = 1

UNION ALL
SELECT   -- Growatt no tiene dimension ni agrupador: el equipo es su propio CodigoOrigen
    'growatt', CAST(g.DeviceId AS nvarchar(200)), CAST(g.DeviceId AS nvarchar(200)), CAST(NULL AS nvarchar(500)),
    CAST(g.DeviceId AS nvarchar(200)), CAST(g.DeviceId AS nvarchar(500)),
    CAST(NULL AS decimal(12,3)), CAST(NULL AS decimal(12,3))
FROM (SELECT DISTINCT DeviceId FROM dw.factGrowattEnergyAndPowerPv) g;
GO

CREATE OR ALTER VIEW dw.vwRptInversor AS
SELECT
    CAST(pl.Planta AS nvarchar(30))                                AS Planta,
    CAST(e.Serie AS nvarchar(30))                                  AS InversorId,
    e.Proveedor,
    CAST(e.DeviceKey AS nvarchar(50))                              AS DeviceKey,
    COALESCE(e.CapacidadDcPortalKwp, c.CapacityDcKwp)              AS CapacidadDcKwp,
    COALESCE(e.CapacidadAcPortalKw,  c.CapacityAcKw)               AS CapacidadAcKw,
    pl.EnReporte,
    e.CodigoOrigen,
    e.Serie,
    e.NombrePortal,
    CAST(CASE WHEN e.CapacidadDcPortalKwp IS NOT NULL THEN 'portal'
              WHEN c.CapacityDcKwp IS NOT NULL       THEN 'dimDeviceCapacity' END AS varchar(20)) AS FuenteCapacidad
FROM dw.vwSolarEquipo e
JOIN dw.dimPlantaSolarOrigen o
  ON o.Proveedor = e.Proveedor AND o.CodigoOrigen = e.CodigoOrigen AND o.EsVigente = 1
JOIN dw.dimPlantaSolar pl
  ON pl.Planta = o.Planta AND pl.EsVigente = 1
OUTER APPLY (
    SELECT TOP (1) dc.CapacityDcKwp, dc.CapacityAcKw
    FROM dw.dimDeviceCapacity dc
    WHERE dc.EsVigente = 1
      AND dc.Vendor = e.Proveedor
      AND (dc.JoinKey = e.DeviceKey OR (dc.Vendor = 'huawei' AND dc.SourceSn = e.NombrePortal))
    ORDER BY CASE WHEN dc.JoinKey = e.DeviceKey THEN 0 ELSE 1 END
) c;
GO

CREATE OR ALTER VIEW dw.vwRptPlanta AS
SELECT
    p.Planta,
    p.Orden,
    p.MeteoSite,                    -- dw.factMeteoDaily.Site
    SUM(i.CapacidadDcKwp) AS CapacidadDcKwp,
    SUM(i.CapacidadAcKw)  AS CapacidadAcKw,
    COUNT(*)              AS Inversores
FROM dw.dimPlantaSolar p
JOIN dw.vwRptInversor i ON i.Planta = p.Planta
WHERE p.EsVigente = 1 AND p.EnReporte = 1
GROUP BY p.Planta, p.Orden, p.MeteoSite;
GO

CREATE OR ALTER VIEW dw.vwRptPlantel AS
SELECT r.Planta,
       CAST(p.Plantel AS nvarchar(30)) AS Plantel
FROM dw.vwRptPlanta r
JOIN dw.dimPlantaSolar p ON p.Planta = r.Planta AND p.EsVigente = 1;
GO

CREATE OR ALTER VIEW dw.vwRptPlanPlantaDia AS
SELECT
    i.Planta,
    p.Fecha,
    NULLIF(SUM(p.PlanDiarioInversor), 0) AS PlanKwh,
    COUNT(*)                             AS InversoresConPlan
FROM dw.dimPlanGeneracion p
JOIN dw.vwRptInversor i ON i.Proveedor = p.Proveedor AND i.DeviceKey = p.Inversor
WHERE p.EsVigente = 1
GROUP BY i.Planta, p.Fecha;
GO

CREATE OR ALTER VIEW dw.vwRptPlanInversorDia AS
SELECT
    i.Planta,
    i.InversorId,
    p.Fecha,
    NULLIF(p.PlanDiarioInversor, 0) AS PlanKwh
FROM dw.dimPlanGeneracion p
JOIN dw.vwRptInversor i ON i.Proveedor = p.Proveedor AND i.DeviceKey = p.Inversor
WHERE p.EsVigente = 1;
GO

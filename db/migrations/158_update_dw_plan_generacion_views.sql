-- 158: vistas del plan de generacion diario, redefinidas con las columnas de la 155.
-- Todas usan solo la version vigente del plan (EsVigente = 1).
--
--   vwPlanDiarioInversor  plan por fecha e inversor, con planta, proveedor y ubicacion.
--   vwPlanDiarioPI        plan por fecha y planta (PI). El plan de la planta es
--                         PlanDiarioAsignado, que el archivo repite en cada inversor:
--                         se toma UNA vez por planta y dia (MAX) y NO se suma entre
--                         inversores. PlanInversoresKwhDia = suma de los planes de los
--                         inversores; si difiere del plan de la planta, hay inversores con
--                         capacidad faltante en el archivo (ej. EDIF ADMIN, MARGARINA).
--   vwPlanDiarioPlantel   plan por fecha y plantel (Ubicacion: 'Km 13.5' / 'Km 15').
-- Para filas de versiones anteriores sin Planta, la planta/ubicacion se deduce de las
-- dimensiones de SMA (OLEPSA = Km 13.5, INDASA = Km 15).

CREATE OR ALTER VIEW dw.vwPlanDiarioInversor
AS
SELECT
    p.Fecha,
    p.CodigoInversor,
    p.Proveedor,
    COALESCE(p.Planta, pl.PlantName)   AS Planta,
    COALESCE(CASE UPPER(p.Ubicacion) WHEN 'KM13.5' THEN 'Km 13.5' WHEN 'KM15' THEN 'Km 15' ELSE p.Ubicacion END,
             CASE WHEN pl.PlantName LIKE 'OLEPSA%' THEN 'Km 13.5' WHEN pl.PlantName LIKE 'INDASA%' THEN 'Km 15' END)
                                       AS Plantel,
    p.SmaDeviceKey,
    p.HuaweiDeviceKey,
    p.SoliscloudDeviceKey,
    p.DeviceCapacityKey,
    p.PlanKwh                          AS PlanKwhDia,
    p.PlanDiarioAsignado,
    p.PlanVersion
FROM dw.dimPlanGeneracion p
LEFT JOIN dw.dimSmaDevices d ON d.SmaDeviceKey = p.SmaDeviceKey
LEFT JOIN dw.dimSmaPlants pl ON pl.SmaPlantaKey = d.SmaPlantaKey
WHERE p.EsVigente = 1;
GO

CREATE OR ALTER VIEW dw.vwPlanDiarioPI
AS
SELECT
    v.Fecha,
    v.Planta                                              AS PI,
    MAX(v.Plantel)                                        AS Plantel,
    COUNT(*)                                              AS InversoresConPlan,
    COALESCE(MAX(v.PlanDiarioAsignado), SUM(v.PlanKwhDia)) AS PlanKwhDia,
    SUM(v.PlanKwhDia)                                     AS PlanInversoresKwhDia
FROM dw.vwPlanDiarioInversor v
WHERE v.Planta IS NOT NULL
GROUP BY v.Fecha, v.Planta;
GO

CREATE OR ALTER VIEW dw.vwPlanDiarioPlantel
AS
SELECT
    x.Fecha,
    COALESCE(x.Plantel, 'Sin plantel')  AS Plantel,
    SUM(x.InversoresConPlan)            AS InversoresConPlan,
    COUNT(*)                            AS Plantas,
    SUM(x.PlanKwhDia)                   AS PlanKwhDia
FROM dw.vwPlanDiarioPI x
GROUP BY x.Fecha, COALESCE(x.Plantel, 'Sin plantel');
GO

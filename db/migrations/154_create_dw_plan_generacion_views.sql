-- 154: vistas del plan de generacion diario. Todas usan solo la version vigente
-- del plan (EsVigente = 1) y se calculan en el DW a partir del plan por inversor
-- (dw.dimPlanGeneracion); los resumenes por PI y por plantel usan las
-- dimensiones de dispositivos que ya manejamos, no las pestanas del Excel.
--
--   vwPlanDiarioInversor  plan por fecha e inversor, con su dispositivo y planta SMA.
--   vwPlanDiarioPI        suma por fecha y PI. PI = planta de dw.dimSmaPlants
--                         (INDASA 1 PROALSA, OLEPSA 3 - JABON, ...). Solo inversores
--                         SMA resueltos (SmaDeviceKey no nulo); el resto no tiene aun
--                         dimension de planta.
--   vwPlanDiarioPlantel   suma por fecha y plantel: OLEPSA = 'Km 13.5', INDASA =
--                         'Km 15' (segun el prefijo del nombre de la planta; una planta
--                         sin ese prefijo, ej. 'PI1-MARGARINA', queda como 'Sin plantel').
-- Solo cubren los inversores que traiga el plan (hoy los 24 SMA de la pestana
-- Plan_Diario_INV; no incluye DETERGENTE, EDIF ADMIN ni MARGARINA).

CREATE OR ALTER VIEW dw.vwPlanDiarioInversor
AS
SELECT
    p.Fecha,
    p.CodigoInversor,
    p.SmaDeviceKey,
    d.SmaPlantaKey,
    pl.PlantName            AS PI,
    p.PlanKwh               AS PlanKwhDia,
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
    v.SmaPlantaKey,
    v.PI,
    COUNT(*)                AS InversoresConPlan,
    SUM(v.PlanKwhDia)       AS PlanKwhDia
FROM dw.vwPlanDiarioInversor v
WHERE v.SmaPlantaKey IS NOT NULL
GROUP BY v.Fecha, v.SmaPlantaKey, v.PI;
GO

CREATE OR ALTER VIEW dw.vwPlanDiarioPlantel
AS
SELECT
    x.Fecha,
    x.Plantel,
    SUM(x.InversoresConPlan)  AS InversoresConPlan,
    SUM(x.PlanKwhDia)         AS PlanKwhDia
FROM (
    SELECT
        pi.Fecha,
        CASE WHEN pi.PI LIKE 'OLEPSA%' THEN 'Km 13.5'
             WHEN pi.PI LIKE 'INDASA%' THEN 'Km 15'
             ELSE 'Sin plantel' END   AS Plantel,
        pi.InversoresConPlan,
        pi.PlanKwhDia
    FROM dw.vwPlanDiarioPI pi
) x
GROUP BY x.Fecha, x.Plantel;
GO

-- 161: vistas del plan de generacion diario sobre la estructura de la 159. Solo usan la version
-- vigente (EsVigente = 1) y solo campos del Excel; no dependen de las dimensiones de dispositivos.
--
--   vwPlanDiarioInversor  plan por fecha e inversor.
--   vwPlanDiarioPI        plan por fecha y planta (PI). PlanKwhDia = plan de la planta
--                         (PlanDiarioAsignado, que el archivo repite en cada inversor: se toma UNA
--                         vez por planta y dia con MAX, nunca SUM); PlanInversoresKwhDia = suma de
--                         los planes de sus inversores.
--   vwPlanDiarioPlantel   plan por fecha y plantel (Ubicacion: 'Km 13.5' / 'Km 15').

CREATE OR ALTER VIEW dw.vwPlanDiarioInversor
AS
SELECT
    p.Fecha,
    p.Planta,
    p.Proveedor,
    p.Inversor,
    p.InversorId,
    CASE UPPER(p.Ubicacion) WHEN 'KM13.5' THEN 'Km 13.5' WHEN 'KM15' THEN 'Km 15' ELSE p.Ubicacion END AS Plantel,
    p.PlanDiarioInversor              AS PlanKwhDia,
    p.PlanDiarioAsignado,
    p.PlanVersion
FROM dw.dimPlanGeneracion p
WHERE p.EsVigente = 1;
GO

CREATE OR ALTER VIEW dw.vwPlanDiarioPI
AS
SELECT
    v.Fecha,
    v.Planta                          AS PI,
    MAX(v.Plantel)                    AS Plantel,
    COUNT(*)                          AS InversoresConPlan,
    MAX(v.PlanDiarioAsignado)         AS PlanKwhDia,
    SUM(v.PlanKwhDia)                 AS PlanInversoresKwhDia
FROM dw.vwPlanDiarioInversor v
GROUP BY v.Fecha, v.Planta;
GO

CREATE OR ALTER VIEW dw.vwPlanDiarioPlantel
AS
SELECT
    x.Fecha,
    x.Plantel,
    SUM(x.InversoresConPlan)          AS InversoresConPlan,
    COUNT(*)                          AS Plantas,
    SUM(x.PlanKwhDia)                 AS PlanKwhDia
FROM dw.vwPlanDiarioPI x
GROUP BY x.Fecha, x.Plantel;
GO

-- 154: vistas del plan de generacion diario. Reproducen la regla del Reporte
-- Ejecutivo (hojas Plan_Diario_Plantel y Plan_Diario_PI), a partir del plan
-- mensual vigente:
--   plan diario del plantel = plan del mes / dias del mes (reparto plano)
--   plan diario del PI      = plan diario del plantel x CapacidadDcKwp del PI
--                             / suma de CapacidadDcKwp de los PI de ese plantel
-- Solo usan la version vigente del plan (EsVigente = 1) y los PI vigentes.
--
-- NOTA: se calcula con la Ubicacion (plantel) de cada PI segun el catalogo.
-- En el Excel de origen (Solar Jaremar - Reporte Ejecutivo, 2026-08) las
-- formulas de Plan_Diario_PI de MARGARINA y DETERGENTE usan el plan de Km 15
-- (estan en Km 13.5) y la de EDIF ADMIN usa el de Km 13.5 (esta en Km 15), por
-- lo que la suma de sus PI no cuadra con el plan del plantel; estas vistas si
-- cuadran (suma de PI = plan del plantel). Los otros 5 PI coinciden con el Excel.
-- Se calcula en FLOAT y se entrega con 6 decimales para no perder precision
-- por la escala de la division decimal.

CREATE OR ALTER VIEW dw.vwPlanDiarioPlantel
AS
SELECT
    DATEFROMPARTS(p.Anio, p.Mes, d.Dia)                                                          AS Fecha,
    p.Anio,
    p.Mes,
    p.Plantel,
    CAST(CAST(p.PlanKwh AS FLOAT) / DAY(EOMONTH(DATEFROMPARTS(p.Anio, p.Mes, 1))) AS DECIMAL(18,6)) AS PlanKwhDia,
    p.PlanVersion
FROM dw.dimPlanGeneracionMensual p
CROSS APPLY (
    SELECT TOP (DAY(EOMONTH(DATEFROMPARTS(p.Anio, p.Mes, 1))))
           ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS Dia
    FROM sys.all_columns
) d
WHERE p.EsVigente = 1;
GO

CREATE OR ALTER VIEW dw.vwPlanDiarioPI
AS
SELECT
    pl.Fecha,
    pl.Anio,
    pl.Mes,
    pl.Plantel,
    pi.CodigoPI,
    pi.CodigoSitio,
    CAST(CAST(pl.PlanKwhDia AS FLOAT) * pi.CapacidadDcKwp
         / SUM(CAST(pi.CapacidadDcKwp AS FLOAT)) OVER (PARTITION BY pl.Fecha, pl.Plantel) AS DECIMAL(18,6)) AS PlanKwhDia,
    pl.PlanVersion
FROM dw.vwPlanDiarioPlantel pl
JOIN dw.dimPlantaSolar pi ON pi.Plantel = pl.Plantel AND pi.EsVigente = 1;
GO

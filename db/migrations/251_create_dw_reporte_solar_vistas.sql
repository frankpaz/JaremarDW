-- 251: versiona las vistas y funciones del "Informe Ejecutivo - Solar Jaremar" (RDL), que hasta hoy
-- vivian solo en produccion y en los scripts sql/01-04 del Escritorio (carpeta "15 Fotovoltaico").
-- Copia FIEL de produccion al 2026-10-05 (OBJECT_DEFINITION; identica a los scripts 01-04), solo
-- con CREATE OR ALTER para que sea idempotente. No cambia ningun resultado del reporte.
--
-- Incluye dw.vwDailyGenerationSummary, que el reporte usa y no estaba en ninguna migracion (la creo
-- el proceso externo). Orden = dependencias:
--   vwDailyGenerationSummary -> vwRptInversor -> vwRptPlanta -> vwRptInversorDia / vwRptMeteoPlantaDia /
--   vwRptPlanPlantaDia -> vwRptPlantaDia -> vwRptDisponibilidadDia -> vwRptPlanInversorDia / vwRptPlantel /
--   vwRptDisponibilidadPlantaDia -> fnRptInforme / fnRptRankingInversor
--
-- De aqui en adelante, cualquier cambio a estos objetos se hace con una migracion nueva (la 252 agrega SOLIS).

CREATE OR ALTER VIEW [dw].[vwDailyGenerationSummary] AS SELECT
    'sma'        AS Provider,
    DeviceId,
    CAST([Time] AS date)     AS GenerationDate,
    PvGeneration / 1000.0    AS EnergyKwh,
    CAST(NULL AS decimal(18,3)) AS GridSellKwh,
    CAST(NULL AS decimal(18,3)) AS GridPurchaseKwh
FROM dw.factSmaPower15Minutes
WHERE Resolution = 'OneDay'

UNION ALL

SELECT
    'growatt'    AS Provider,
    DeviceId,
    CAST([Time] AS date) AS GenerationDate,
    MAX(EacToday)        AS EnergyKwh,
    CAST(NULL AS decimal(18,3))  AS GridSellKwh,
    CAST(NULL AS decimal(18,3))AS GridPurchaseKwh 
FROM dw.factGrowattEnergyAndPowerPv
GROUP BY DeviceId, CAST([Time] AS date)

UNION ALL

SELECT
    'huawei'     AS Provider,
    DeviceId,
    CAST([Time] AS date) AS GenerationDate,
    ProductPower AS EnergyKwh,
    CAST(NULL AS decimal(18,3)) AS GridSellKwh,
    CAST(NULL AS decimal(18,3)) AS GridPurchaseKwh 
FROM dw.factHuaweiEnergyAndPowerPv


UNION ALL

SELECT
    'soliscloud' AS Provider,
    DeviceId,
    CAST([Time] AS date) AS GenerationDate,
    MAX(EToday)                 AS EnergyKwh,
    MAX(GridSellTodayEnergy)    AS GridSellKwh,
    MAX(GridPurchasedTodayEnergy) AS GridPurchaseKwh
FROM dw.factSoliscloudEnergyAndPowerPv
GROUP BY 
	DeviceId,
	CAST([Time] AS date);
GO

-- 01_vistasBase.sql : inversores y plantas del Reporte Ejecutivo Solar Jaremar, derivados de las dimensiones existentes.
-- No crea tablas. Fuentes:
--   SMA               -> dw.dimSmaDevices + dw.dimSmaPlants
--   Growatt / Huawei / Solis -> dw.dimDeviceCapacity (unico lugar con nombre de reporte y capacidad) unido a
--                        dw.dimHuaweiDevices / dw.dimSoliscloudDevices para obtener el DeviceId de los hechos.

-- 1) Un renglon por inversor
CREATE OR ALTER VIEW dw.vwRptInversor AS
WITH sma AS (
    SELECT
        CAST(CASE
               WHEN p.PlantName LIKE N'%PROALSA%'   THEN N'PROALSA'
               WHEN p.PlantName LIKE N'%REFINER%'   THEN N'REFINERÍA'
               WHEN p.PlantName LIKE N'%PERFECTOR%' THEN N'PERFECTOR'
               WHEN p.PlantName LIKE N'%JAB%'       THEN N'JABÓN'
               WHEN p.PlantName LIKE N'%HARINA%'    THEN N'HARINAS'
               WHEN p.PlantName LIKE N'%MARGARINA%' THEN N'MARGARINA'
             END AS nvarchar(30))                                        AS Planta,
        -- nombre = texto antes de " (" en DeviceName; si el equipo no tiene nombre ('SN 300...') se deja el SN
        CAST(CASE WHEN d.DeviceName LIKE N'%-%(%'
                  THEN LEFT(d.DeviceName, CHARINDEX(N' (', d.DeviceName) - 1)
                  ELSE N'SN ' + CAST(d.Serial AS nvarchar(30)) END AS nvarchar(30)) AS InversorId,
        CAST('sma' AS varchar(20))                                       AS Proveedor,
        CAST(d.DeviceId AS nvarchar(50))                                 AS DeviceKey,
        CAST(d.GeneratorPowerDc / 1000.0 AS decimal(12,3))               AS CapacidadDcKwp,
        CAST(d.GeneratorPower   / 1000.0 AS decimal(12,3))               AS CapacidadAcKw
    FROM dw.dimSmaDevices d
    JOIN dw.dimSmaPlants  p ON p.PlantId = d.PlantId AND p.EsVigente = 1
    WHERE d.EsVigente = 1
      AND p.PlantName <> N'PI1-MARGARINA'      -- plantel sin datos y con seriales repetidos de otras plantas
),
otros AS (
    SELECT
        CAST(CASE WHEN c.InverterId LIKE N'MARG-%'       THEN N'MARGARINA'
                  WHEN c.Vendor = 'soliscloud'            THEN N'SOLIS'
                  ELSE LEFT(c.InverterId, LEN(c.InverterId) - CHARINDEX(N'-', REVERSE(c.InverterId))) END AS nvarchar(30)) AS Planta,
        CAST(c.InverterId AS nvarchar(30))                               AS InversorId,
        CAST(c.Vendor AS varchar(20))                                    AS Proveedor,
        CAST(CASE c.Vendor
               WHEN 'growatt'    THEN c.JoinKey
               WHEN 'soliscloud' THEN c.JoinKey
               WHEN 'huawei'     THEN h.DeviceId
             END AS nvarchar(50))                                        AS DeviceKey,
        c.CapacityDcKwp                                                  AS CapacidadDcKwp,
        c.CapacityAcKw                                                   AS CapacidadAcKw
    FROM dw.dimDeviceCapacity c
    LEFT JOIN dw.dimHuaweiDevices h
           ON c.Vendor = 'huawei' AND h.DeviceName = c.SourceSn AND h.EsVigente = 1
    WHERE c.EsVigente = 1
      AND c.Vendor IN ('growatt', 'huawei', 'soliscloud')
)
SELECT Planta, InversorId, Proveedor, DeviceKey, CapacidadDcKwp, CapacidadAcKw,
       CAST(CASE WHEN Planta <> N'SOLIS' THEN 1 ELSE 0 END AS bit) AS EnReporte   -- Solis no se reporta en el PDF
FROM (SELECT * FROM sma UNION ALL SELECT * FROM otros) x
WHERE DeviceKey IS NOT NULL;
GO

-- 2) Un renglon por planta del reporte (capacidad = suma de sus inversores)
CREATE OR ALTER VIEW dw.vwRptPlanta AS
SELECT
    Planta,
    CASE Planta WHEN N'PROALSA' THEN 1 WHEN N'REFINERÍA' THEN 2 WHEN N'PERFECTOR' THEN 3 WHEN N'EDIF ADMIN' THEN 4
                WHEN N'MARGARINA' THEN 5 WHEN N'DETERGENTE' THEN 6 WHEN N'JABÓN' THEN 7 WHEN N'HARINAS' THEN 8 END AS Orden,
    CASE Planta WHEN N'PROALSA' THEN N'proalsa' WHEN N'REFINERÍA' THEN N'refineria' WHEN N'PERFECTOR' THEN N'perfector'
                WHEN N'EDIF ADMIN' THEN N'edif-admin' WHEN N'MARGARINA' THEN N'margarina' WHEN N'DETERGENTE' THEN N'detergentes'
                WHEN N'JABÓN' THEN N'jabon' WHEN N'HARINAS' THEN N'harina' END                                       AS MeteoSite,   -- dw.factMeteoDaily.Site
    SUM(CapacidadDcKwp) AS CapacidadDcKwp,
    SUM(CapacidadAcKw)  AS CapacidadAcKw,
    COUNT(*)            AS Inversores
FROM dw.vwRptInversor
WHERE EnReporte = 1
GROUP BY Planta;
GO

-- 02_vistasReporte.sql : vistas que alimentan el RDL "Informe Ejecutivo - Solar Jaremar"
-- Requiere 01_vistasBase.sql. Todas son de solo lectura sobre las tablas existentes.
-- Grano: una fila por inversor/planta y dia. El RDL agrega HOY / MES / ANIO con el parametro @Fecha.

-- 1) Generacion por inversor y dia (alimenta el grafico Top 10 vs Top inferior y la disponibilidad)
CREATE OR ALTER VIEW dw.vwRptInversorDia AS
SELECT
    i.InversorId,
    i.Planta,
    i.EnReporte AS EnDisponibilidad,
    g.GenerationDate                                   AS Fecha,
    g.EnergyKwh,
    i.CapacidadDcKwp,
    CASE WHEN i.CapacidadDcKwp > 0 THEN g.EnergyKwh / i.CapacidadDcKwp END AS YieldKwhKwp
FROM dw.vwRptInversor i
JOIN dw.vwDailyGenerationSummary g
  ON g.Provider = i.Proveedor
 AND g.DeviceId = i.DeviceKey COLLATE DATABASE_DEFAULT;
GO

-- 2) Meteorologia por planta y dia. Real = factMeteoDaily (NULL si no hay medicion), Plan = dimGhiPlanDaily.
--    Calendario del anio 2026 para que el plan exista aunque no haya medicion.
CREATE OR ALTER VIEW dw.vwRptMeteoPlantaDia AS
WITH cal AS (
    SELECT DATEADD(DAY, n, CAST('2026-01-01' AS date)) AS Fecha
    FROM (SELECT TOP (365) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n
          FROM sys.all_objects) t
)
SELECT
    c.Fecha,
    p.Planta,
    m.HsfRealHrs,
    pl.HsfP50Hrs                          AS HsfPlanHrs,
    m.GhiRealWhM2 / 1000.0                AS RadiacionRealKwhM2,
    pl.GhiP50WhM2 / 1000.0                AS RadiacionPlanKwhM2
FROM cal c
CROSS JOIN dw.vwRptPlanta p
LEFT JOIN dw.factMeteoDaily m
       ON m.Site = p.MeteoSite COLLATE DATABASE_DEFAULT
      AND m.MeasuredDate = c.Fecha
      AND m.EsVigente = 1
LEFT JOIN dw.dimGhiPlanDaily pl
       ON pl.Site = p.MeteoSite COLLATE DATABASE_DEFAULT
      AND pl.MonthOfYear = MONTH(c.Fecha)
      AND pl.DayOfMonth  = DAY(c.Fecha)
      AND pl.EsVigente = 1;
GO

CREATE OR ALTER VIEW dw.vwRptPlanPlantaDia AS
SELECT
    p.Planta,
    p.Fecha,
    NULLIF(SUM(p.PlanDiarioInversor), 0) AS PlanKwh,
    COUNT(*)                             AS InversoresConPlan
FROM dw.dimPlanGeneracion p
WHERE p.EsVigente = 1
GROUP BY p.Planta, p.Fecha;
GO

-- 3b) Generacion real, plan, rendimiento especifico y PR por planta y dia (real y plan).
--     Rendimiento = kWh / kWp DC de la planta (igual que el Excel: PROALSA 1867.22/457.64 = 4.08).
--     PR real = Rendimiento real / HSF real (NULL sin medicion). PR plan = Rendimiento plan / HSF plan.
--     FULL JOIN: un dia con plan y sin generacion (o al reves) sigue apareciendo.
CREATE OR ALTER VIEW dw.vwRptPlantaDia AS
SELECT
    x.Fecha,
    p.Planta,
    p.Orden,
    p.CapacidadDcKwp,
    x.EnergiaKwh,
    x.PlanKwh,
    x.InversoresConDato,
    x.EnergiaKwh / NULLIF(p.CapacidadDcKwp, 0)                           AS YieldKwhKwp,
    x.PlanKwh    / NULLIF(p.CapacidadDcKwp, 0)                           AS YieldPlanKwhKwp,
    m.HsfRealHrs,
    m.HsfPlanHrs,
    x.EnergiaKwh / NULLIF(p.CapacidadDcKwp, 0) / NULLIF(m.HsfRealHrs, 0) AS PrReal,
    x.PlanKwh    / NULLIF(p.CapacidadDcKwp, 0) / NULLIF(m.HsfPlanHrs, 0) AS PrPlan
FROM (
    SELECT COALESCE(e.Planta, pl.Planta) AS Planta, COALESCE(e.Fecha, pl.Fecha) AS Fecha,
           e.EnergiaKwh, e.InversoresConDato, pl.PlanKwh
    FROM (
        SELECT Planta, Fecha, SUM(EnergyKwh) AS EnergiaKwh, COUNT(*) AS InversoresConDato
        FROM dw.vwRptInversorDia
        GROUP BY Planta, Fecha
    ) e
    FULL JOIN dw.vwRptPlanPlantaDia pl ON pl.Planta = e.Planta AND pl.Fecha = e.Fecha
) x
JOIN dw.vwRptPlanta p ON p.Planta = x.Planta
LEFT JOIN dw.vwRptMeteoPlantaDia m ON m.Planta = x.Planta AND m.Fecha = x.Fecha;
GO

-- 4) Disponibilidad de inversores por dia.
--    Regla del Excel (Disponibilidad_INV): un inversor con 0 kWh cuenta como perdido cuando el resto de su PI
--    explica la generacion del PI; como el PI es la suma de sus inversores, equivale a contar inversores en 0.
--    Un inversor sin fila ese dia (dejo de reportar) cuenta como 0 kWh, igual que en el Excel, pero solo a partir
--    de la primera fecha en que tuvo datos (asi no penaliza inversores que aun no se habian integrado).
CREATE OR ALTER VIEW dw.vwRptDisponibilidadDia AS
WITH w AS (   -- una sola lectura de la vista pesada (referenciarla varias veces la recalcula cada vez)
    SELECT Fecha, EnergyKwh,
           MIN(Fecha) OVER (PARTITION BY InversorId) AS Desde        -- primera fecha con datos del inversor
    FROM dw.vwRptInversorDia
    WHERE EnDisponibilidad = 1
),
f AS (
    SELECT Fecha,
           SUM(CASE WHEN EnergyKwh > 0 THEN 1 ELSE 0 END) AS Generando,   -- inversores con kWh > 0
           SUM(CASE WHEN Fecha = Desde THEN 1 ELSE 0 END) AS Nuevos       -- inversores que entran ese dia
    FROM w
    GROUP BY Fecha
),
g AS (
    SELECT Fecha, Generando,
           SUM(Nuevos) OVER (ORDER BY Fecha ROWS UNBOUNDED PRECEDING) AS Inversores   -- inversores ya integrados
    FROM f
)
-- perdido = integrado y sin generar (kWh = 0 o sin fila ese dia)
SELECT Fecha,
       Inversores,
       Inversores - Generando                              AS InversoresPerdidos,
       Generando * 1.0 / NULLIF(Inversores, 0)             AS DisponibilidadPct
FROM g;
GO

-- 04_vistasPlanBI.sql : vistas PROPUESTAS para el modelo de Power BI (real vs plan).
-- NO DESPLEGADO TODAVIA. Revisar y ejecutar cuando el usuario lo confirme (mismo patron que 01-03:
-- CREATE OR ALTER, solo lectura sobre objetos existentes, sin tablas nuevas, probar con
-- transaccion + ROLLBACK antes de confirmar).
-- Requiere 01_vistasBase.sql y 02_vistasReporte.sql.
--
-- IMPORTANTE: dw.vwRptDisponibilidadPlantaDia (vista 3) ya NO es opcional. El filtro por
-- Proveedor/Inversor de 03_funcionesInforme.sql (fnRptInforme) la usa para poder acotar la
-- disponibilidad a las plantas en alcance; hay que desplegarla ANTES que los cambios de 03.

-- 1) Plan de generacion a grano Inversor x Dia (hoy dimPlanGeneracion solo se consume agregado
--    por planta en vwRptPlanPlantaDia). Habilita el Pareto de perdida por inversor en Power BI.
--    Mismo filtro EsVigente = 1 que vwRptPlanPlantaDia; un plan de 0 se deja vacio (NULLIF) igual
--    que alli (p. ej. EDIF ADMIN, PlanDiarioInversor = 0 por capacidad 0).
CREATE OR ALTER VIEW dw.vwRptPlanInversorDia AS
SELECT
    p.Planta,
    p.InversorId,
    p.Fecha,
    NULLIF(p.PlanDiarioInversor, 0) AS PlanKwh
FROM dw.dimPlanGeneracion p
WHERE p.EsVigente = 1;
GO

-- Verificacion sugerida al desplegar: SUM(PlanKwh) por Planta/Fecha debe coincidir exacto con
-- dw.vwRptPlanPlantaDia.PlanKwh (misma fuente, distinto grano).

-- 2) Mapeo Planta -> Plantel (Km 13.5 / Km 15), tomado de la hoja "PI" del Excel de referencia.
--    OJO: esta correspondencia no existe hoy en ninguna tabla de dw revisada; se deja como lista
--    fija de 8 filas. Si se agrega una planta nueva al reporte, hay que agregarla aqui a mano.
--    Confirmar con el usuario si conviene moverla a una tabla dw.dimPlantel en vez de un CASE.
CREATE OR ALTER VIEW dw.vwRptPlantel AS
SELECT Planta,
       CAST(CASE Planta
              WHEN N'HARINAS'     THEN N'Km 13.5'
              WHEN N'DETERGENTE'  THEN N'Km 13.5'
              WHEN N'MARGARINA'   THEN N'Km 13.5'
              WHEN N'JABÓN'       THEN N'Km 13.5'
              WHEN N'PERFECTOR'   THEN N'Km 15'
              WHEN N'PROALSA'     THEN N'Km 15'
              WHEN N'REFINERÍA'   THEN N'Km 15'
              WHEN N'EDIF ADMIN'  THEN N'Km 15'
            END AS nvarchar(10)) AS Plantel
FROM dw.vwRptPlanta;
GO

-- 3) Disponibilidad de inversores por dia, particionada por Planta (vwRptDisponibilidadDia hoy
--    es un solo numero global). Misma logica que esa vista, agregando Planta al PARTITION BY.
CREATE OR ALTER VIEW dw.vwRptDisponibilidadPlantaDia AS
WITH w AS (
    SELECT Planta, Fecha, EnergyKwh,
           MIN(Fecha) OVER (PARTITION BY InversorId) AS Desde
    FROM dw.vwRptInversorDia
    WHERE EnDisponibilidad = 1
),
f AS (
    SELECT Planta, Fecha,
           SUM(CASE WHEN EnergyKwh > 0 THEN 1 ELSE 0 END) AS Generando,
           SUM(CASE WHEN Fecha = Desde THEN 1 ELSE 0 END) AS Nuevos
    FROM w
    GROUP BY Planta, Fecha
),
g AS (
    SELECT Planta, Fecha, Generando,
           SUM(Nuevos) OVER (PARTITION BY Planta ORDER BY Fecha ROWS UNBOUNDED PRECEDING) AS Inversores
    FROM f
)
SELECT Planta, Fecha, Inversores,
       Inversores - Generando                          AS InversoresPerdidos,
       Generando * 1.0 / NULLIF(Inversores, 0)          AS DisponibilidadPct
FROM g;
GO

-- 03_funcionesInforme.sql : datasets del RDL "Informe Ejecutivo - Solar Jaremar". Requiere 01 y 02.
-- Reglas del informe (tomadas del Excel de referencia):
--   * HOY = @Fecha; MES = del dia 1 a @Fecha; ANIO = del 1-ene a @Fecha.
--   * Generacion y Radiacion/Horas Sol: suma del periodo.
--   * Rendimiento especifico = kWh / kWp / dias transcurridos del periodo (promedio diario).
--   * PR = generacion / (kWp x Horas Sol Full) sobre los dias con generacion y horas sol.
--   * % = (Real - Plan) / Plan.

-- 1) Cuerpo del informe: una fila por concepto, con Hoy / Mes / Anio (Real, Plan, %).
--    @Proveedores / @Inversores: filtro opcional (listas separadas por coma; NULL o '' = todos).
--    Estructura Planta > Inversor: al filtrar, el informe completo (tabla, meteo, disponibilidad)
--    se acota a las Plantas que tengan al menos un inversor que cumpla el filtro (CTE pls).
--    Sin filtro (ambos NULL), el resultado es identico al de antes de este cambio.
CREATE OR ALTER FUNCTION dw.fnRptInforme (@Fecha date, @Proveedores nvarchar(400) = NULL, @Inversores nvarchar(400) = NULL)
RETURNS TABLE
AS RETURN
WITH par AS (
    SELECT NULLIF(LTRIM(RTRIM(@Proveedores)), '') AS Proveedores,
           NULLIF(LTRIM(RTRIM(@Inversores)), '')  AS Inversores
),
pls AS (   -- Plantas en alcance segun el filtro de Proveedor/Inversor
    SELECT pl.Planta
    FROM dw.vwRptPlanta pl
    CROSS JOIN par
    WHERE (par.Proveedores IS NULL AND par.Inversores IS NULL)
       OR EXISTS (
            SELECT 1 FROM dw.vwRptInversor i
            WHERE i.Planta = pl.Planta
              AND (par.Proveedores IS NULL OR i.Proveedor  IN (SELECT value FROM STRING_SPLIT(par.Proveedores, ',')))
              AND (par.Inversores  IS NULL OR i.InversorId IN (SELECT value FROM STRING_SPLIT(par.Inversores, ',')))
          )
),
per AS (
    SELECT CAST('HOY'  AS varchar(4)) AS P, @Fecha AS D1, @Fecha AS D2, 1 AS Dias
    UNION ALL SELECT 'MES',  DATEFROMPARTS(YEAR(@Fecha), MONTH(@Fecha), 1), @Fecha, DAY(@Fecha)
    UNION ALL SELECT 'ANIO', DATEFROMPARTS(YEAR(@Fecha), 1, 1), @Fecha,
                             DATEDIFF(DAY, DATEFROMPARTS(YEAR(@Fecha), 1, 1), @Fecha) + 1
),
-- planta x periodo (las plantas en alcance siempre aparecen, aunque no tengan datos)
pd AS (
    SELECT per.P, per.Dias, pl.Planta, pl.Orden, pl.CapacidadDcKwp AS Cap,
           v.EnergiaKwh, v.PlanKwh, v.HsfRealHrs, v.HsfPlanHrs
    FROM per
    CROSS JOIN dw.vwRptPlanta pl
    JOIN pls ON pls.Planta = pl.Planta
    LEFT JOIN dw.vwRptPlantaDia v
           ON v.Planta = pl.Planta AND v.Fecha BETWEEN per.D1 AND per.D2
),
pa AS (
    SELECT P, Planta, Orden, Cap, Dias,
           SUM(EnergiaKwh)                                                        AS RealKwh,
           SUM(PlanKwh)                                                           AS PlanKwh,
           SUM(CASE WHEN PlanKwh IS NOT NULL THEN EnergiaKwh END)                 AS RealMKwh,   -- real solo de dias con plan
           SUM(CASE WHEN EnergiaKwh IS NOT NULL AND HsfRealHrs IS NOT NULL THEN EnergiaKwh END)  AS ERealPr,
           SUM(CASE WHEN EnergiaKwh IS NOT NULL AND HsfRealHrs IS NOT NULL THEN HsfRealHrs END)  AS HRealPr,
           SUM(CASE WHEN PlanKwh    IS NOT NULL AND HsfPlanHrs IS NOT NULL THEN PlanKwh    END)  AS EPlanPr,
           SUM(CASE WHEN PlanKwh    IS NOT NULL AND HsfPlanHrs IS NOT NULL THEN HsfPlanHrs END)  AS HPlanPr
    FROM pd
    GROUP BY P, Planta, Orden, Cap, Dias
),
-- meteorologia: promedio entre las plantas EN ALCANCE (pls) por dia
md AS (
    SELECT m.Fecha, AVG(m.RadiacionRealKwhM2) AS RadR, AVG(m.RadiacionPlanKwhM2) AS RadP,
                    AVG(m.HsfRealHrs) AS HsfR, AVG(m.HsfPlanHrs) AS HsfP
    FROM dw.vwRptMeteoPlantaDia m
    JOIN pls ON pls.Planta = m.Planta
    GROUP BY m.Fecha
),
ma AS (
    SELECT per.P,
           SUM(m.RadR) AS RadR, SUM(m.HsfR) AS HsfR, COUNT(m.RadR) AS DiasReal,
           -- el plan se compara contra los mismos dias medidos; si no hay ninguno se muestra el plan del periodo
           CASE WHEN COUNT(m.RadR) = 0 THEN SUM(m.RadP) ELSE SUM(CASE WHEN m.RadR IS NOT NULL THEN m.RadP END) END   AS RadP,
           CASE WHEN COUNT(m.RadR) = 0 THEN SUM(m.HsfP) ELSE SUM(CASE WHEN m.RadR IS NOT NULL THEN m.HsfP END) END   AS HsfP
    FROM per
    LEFT JOIN md m ON m.Fecha BETWEEN per.D1 AND per.D2
    GROUP BY per.P
),
-- disponibilidad: reconstruye el mismo calculo global de vwRptDisponibilidadDia
-- (Generando/Inversores por dia) pero sumando solo las plantas en pls, via
-- dw.vwRptDisponibilidadPlantaDia (sql/04_vistasPlanBI.sql). Sin filtro, pls = todas
-- las plantas y esta suma reconstruye exactamente el mismo global de antes.
da AS (
    SELECT per.P, AVG(gg.DispDia) AS DispR
    FROM per
    JOIN (
        SELECT d.Fecha,
               SUM(d.Inversores - d.InversoresPerdidos) * 1.0 / NULLIF(SUM(d.Inversores), 0) AS DispDia
        FROM dw.vwRptDisponibilidadPlantaDia d
        JOIN pls ON pls.Planta = d.Planta
        GROUP BY d.Fecha
    ) gg ON gg.Fecha BETWEEN per.D1 AND per.D2
    GROUP BY per.P
),
-- filas largas: (Seccion, Orden, Concepto, Und, P, Real, Plan)
filas AS (
    -- 1 Generacion total.  RealM = real comparable contra el plan (mismos dias y plantas)
    SELECT 1 AS Sec, Orden AS Ord, Planta AS Concepto, CAST('kWh' AS nvarchar(10)) AS Und, P, RealKwh AS RealV, PlanKwh AS PlanV, RealMKwh AS RealM FROM pa
    UNION ALL
    SELECT 1, 99, N'TOTAL GENERACION', 'kWh', P, SUM(RealKwh), SUM(PlanKwh), SUM(RealMKwh) FROM pa GROUP BY P
    -- 2 Datos meteorologicos
    UNION ALL SELECT 2, 1, N'Radiación Diaria', 'kWh/m2', P, RadR, RadP, RadR FROM ma
    UNION ALL SELECT 2, 2, N'Horas Sol Full',   'h',      P, HsfR, HsfP, HsfR FROM ma
    -- 3 Rendimiento especifico (kWh/kWp por dia)
    UNION ALL SELECT 3, Orden, Planta, 'kWh/kWp', P, RealKwh / NULLIF(Cap * Dias, 0), PlanKwh / NULLIF(Cap * Dias, 0),
                    RealMKwh / NULLIF(Cap * Dias, 0) FROM pa
    UNION ALL SELECT 3, 99, N'TOTAL', 'kWh/kWp', P,
                    SUM(RealKwh) / NULLIF(SUM(Cap) * MAX(Dias), 0),
                    SUM(PlanKwh) / NULLIF(SUM(CASE WHEN PlanKwh IS NOT NULL THEN Cap END) * MAX(Dias), 0),   -- plan solo de plantas con plan
                    SUM(RealMKwh) / NULLIF(SUM(CASE WHEN PlanKwh IS NOT NULL THEN Cap END) * MAX(Dias), 0)
              FROM pa GROUP BY P
    -- 4 PR
    UNION ALL SELECT 4, Orden, Planta, '%', P, ERealPr / NULLIF(Cap * HRealPr, 0), EPlanPr / NULLIF(Cap * HPlanPr, 0),
                    ERealPr / NULLIF(Cap * HRealPr, 0) FROM pa
    UNION ALL SELECT 4, 99, N'TOTAL', '%', P,
                    SUM(ERealPr) / NULLIF(SUM(Cap * HRealPr), 0), SUM(EPlanPr) / NULLIF(SUM(Cap * HPlanPr), 0),
                    SUM(CASE WHEN EPlanPr IS NOT NULL THEN ERealPr END) / NULLIF(SUM(CASE WHEN EPlanPr IS NOT NULL THEN Cap * HRealPr END), 0)
              FROM pa GROUP BY P
    -- 5 Disponibilidad (plan 95 %)
    UNION ALL SELECT 5, 1, N'Disponibilidad de Inversor', '%', P, DispR, CAST(0.95 AS float), DispR FROM da
)
SELECT
    Sec,
    CASE Sec WHEN 1 THEN N'Generación Total' WHEN 2 THEN N'Datos Meteorológicos' WHEN 3 THEN N'Rendimiento Específico'
             WHEN 4 THEN N'PR%' ELSE N'Disponibilidades' END                                   AS Seccion,
    Ord, Concepto, Und,
    MAX(CASE WHEN P = 'HOY'  THEN RealV END) AS HoyReal,
    MAX(CASE WHEN P = 'HOY'  THEN PlanV END) AS HoyPlan,
    MAX(CASE WHEN P = 'HOY'  THEN (RealM - PlanV) / NULLIF(PlanV, 0) END) AS HoyPct,
    MAX(CASE WHEN P = 'MES'  THEN RealV END) AS MesReal,
    MAX(CASE WHEN P = 'MES'  THEN PlanV END) AS MesPlan,
    MAX(CASE WHEN P = 'MES'  THEN (RealM - PlanV) / NULLIF(PlanV, 0) END) AS MesPct,
    MAX(CASE WHEN P = 'ANIO' THEN RealV END) AS AnioReal,
    MAX(CASE WHEN P = 'ANIO' THEN PlanV END) AS AnioPlan,
    MAX(CASE WHEN P = 'ANIO' THEN (RealM - PlanV) / NULLIF(PlanV, 0) END) AS AnioPct
FROM filas
GROUP BY Sec, Ord, Concepto, Und;
GO

-- 2) Ranking de inversores del dia: 10 mejores y 10 peores por PR.
--    PR del inversor = kWh/kWp del dia / Horas Sol Full de su planta (si no hay medicion ese dia, se usa el plan).
--    Un inversor sin generacion ese dia (o sin fila) entra con PR 0, igual que en el informe de referencia.
--    @Proveedores / @Inversores: mismo filtro opcional que fnRptInforme (listas separadas por coma;
--    NULL o '' = todos). El Top10/Top inferior se recalcula sobre el subconjunto filtrado.
CREATE OR ALTER FUNCTION dw.fnRptRankingInversor (@Fecha date, @Proveedores nvarchar(400) = NULL, @Inversores nvarchar(400) = NULL)
RETURNS TABLE
AS RETURN
WITH par AS (
    SELECT NULLIF(LTRIM(RTRIM(@Proveedores)), '') AS Proveedores,
           NULLIF(LTRIM(RTRIM(@Inversores)), '')  AS Inversores
),
base AS (
    SELECT i.InversorId, i.Planta,
           ISNULL(d.YieldKwhKwp, 0) / NULLIF(COALESCE(m.HsfRealHrs, m.HsfPlanHrs), 0) AS Pr
    FROM dw.vwRptInversor i
    CROSS JOIN par
    LEFT JOIN dw.vwRptInversorDia d ON d.InversorId = i.InversorId AND d.Fecha = @Fecha
    LEFT JOIN dw.vwRptMeteoPlantaDia m ON m.Planta = i.Planta AND m.Fecha = @Fecha
    WHERE i.EnReporte = 1
      AND (par.Proveedores IS NULL OR i.Proveedor  IN (SELECT value FROM STRING_SPLIT(par.Proveedores, ',')))
      AND (par.Inversores  IS NULL OR i.InversorId IN (SELECT value FROM STRING_SPLIT(par.Inversores, ',')))
      AND EXISTS (SELECT 1 FROM dw.vwRptInversorDia x WHERE x.InversorId = i.InversorId AND x.Fecha <= @Fecha)
),
r AS (
    SELECT *, ROW_NUMBER() OVER (ORDER BY Pr DESC, InversorId) AS RnDesc,
              ROW_NUMBER() OVER (ORDER BY Pr ASC,  InversorId DESC) AS RnAsc
    FROM base
)
SELECT InversorId, Planta, Pr,
       CASE WHEN RnDesc <= 10 THEN N'TOP' ELSE N'INFERIOR' END AS Grupo,
       RnDesc AS Posicion
FROM r
WHERE RnDesc <= 10 OR RnAsc <= 10;
GO

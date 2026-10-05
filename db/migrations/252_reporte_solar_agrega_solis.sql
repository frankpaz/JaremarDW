-- 252: agrega SOLIS como planta del "Informe Ejecutivo - Solar Jaremar". Hasta hoy se excluia
-- (EnReporte = 0, "Solis no se reporta en el PDF") porque su plan venia en 0; desde la version
-- V2-2026-10-05 de dimPlanGeneracion tiene plan (353.270 kWh en 2026).
--
--   vwRptInversor : EnReporte = 1 para todos (SOLIS: BODEGA GRAL-1 151,83 kWp y HARINA-SOLIS 113,4 kWp).
--                   EnReporte tambien es EnDisponibilidad: sus 2 inversores entran a la disponibilidad.
--   vwRptPlanta   : SOLIS con Orden 9 y MeteoSite 'bodega-jabon' (sitio de NASA POWER sin uso hasta hoy).
--   vwRptPlantel  : SOLIS -> 'Km 13.5'.
--
-- El RDL y fnRptInforme toman las plantas de vwRptPlanta: no hay que tocarlos.

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
       CAST(1 AS bit) AS EnReporte   -- 252: SOLIS tambien se reporta (ya tiene plan desde V2-2026-10-05)
FROM (SELECT * FROM sma UNION ALL SELECT * FROM otros) x
WHERE DeviceKey IS NOT NULL;
GO

-- 2) Un renglon por planta del reporte (capacidad = suma de sus inversores)
CREATE OR ALTER VIEW dw.vwRptPlanta AS
SELECT
    Planta,
    CASE Planta WHEN N'PROALSA' THEN 1 WHEN N'REFINERÍA' THEN 2 WHEN N'PERFECTOR' THEN 3 WHEN N'EDIF ADMIN' THEN 4
                WHEN N'MARGARINA' THEN 5 WHEN N'DETERGENTE' THEN 6 WHEN N'JABÓN' THEN 7 WHEN N'HARINAS' THEN 8 WHEN N'SOLIS' THEN 9 END AS Orden,
    CASE Planta WHEN N'PROALSA' THEN N'proalsa' WHEN N'REFINERÍA' THEN N'refineria' WHEN N'PERFECTOR' THEN N'perfector'
                WHEN N'EDIF ADMIN' THEN N'edif-admin' WHEN N'MARGARINA' THEN N'margarina' WHEN N'DETERGENTE' THEN N'detergentes'
                WHEN N'JABÓN' THEN N'jabon' WHEN N'HARINAS' THEN N'harina' WHEN N'SOLIS' THEN N'bodega-jabon' END                                       AS MeteoSite,   -- dw.factMeteoDaily.Site
    SUM(CapacidadDcKwp) AS CapacidadDcKwp,
    SUM(CapacidadAcKw)  AS CapacidadAcKw,
    COUNT(*)            AS Inversores
FROM dw.vwRptInversor
WHERE EnReporte = 1
GROUP BY Planta;
GO

-- Verificacion sugerida al desplegar: SUM(PlanKwh) por Planta/Fecha debe coincidir exacto con
-- dw.vwRptPlanPlantaDia.PlanKwh (misma fuente, distinto grano).

-- 2) Mapeo Planta -> Plantel (Km 13.5 / Km 15), tomado de la hoja "PI" del Excel de referencia.
--    OJO: esta correspondencia no existe hoy en ninguna tabla de dw revisada; se deja como lista
--    fija (9 filas desde la 252). Si se agrega una planta nueva al reporte, hay que agregarla aqui a mano.
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
              WHEN N'SOLIS'       THEN N'Km 13.5'
            END AS nvarchar(10)) AS Plantel
FROM dw.vwRptPlanta;
GO

-- 262: generacion por inversor y por hora para el dashboard de Power BI (dominio Solar).
-- Una fila por inversor, fecha y hora LOCAL (UTC-6) con los kWh generados en esa hora.
--   SMA        : suma de los intervalos de 15 min. La hora de SMA marca el FIN del intervalo (con
--                ese supuesto la curva queda centrada como la de Growatt/Soliscloud), por eso se le
--                restan 15 min antes de asignar la hora.
--   Growatt    : EacToday es el acumulado del dia, en hora local. kWh de la hora = acumulado al cierre
--                de la hora - acumulado al cierre de la anterior, con maximo corrido para que una
--                lectura que baja no deje horas negativas (la suma del dia = MAX del dia).
--   Soliscloud : igual con EToday, pero la hora viene en UTC: se restan 6 h.
--   Huawei     : no esta; el origen solo trae el total diario.
-- CalidadDia/MotivoCalidad son del inversor y dia (se repiten en sus horas). Aqui no se corrige nada:
-- los datos se corrigen en origen.
--   SMA REVISAR: intervalos negativos, energia entre 19:00 y 05:00 (hora corrida en el proceso
--                externo) o suma de 15 min que no cuadra con su total diario (2 % + 0,1 kWh).
--   Growatt/Soliscloud REVISAR: el acumulado baja durante el dia y no se recupera en la lectura siguiente.
CREATE OR ALTER VIEW dw.vwSolarInversorHora AS
WITH sma AS (
    SELECT CAST(DeviceId AS nvarchar(200)) AS DeviceKey,
           DATEADD(MINUTE, -15, [Time])   AS Inicio,
           PvGeneration / 1000.0          AS Kwh
    FROM dw.factSmaPower15Minutes
    WHERE IsDeleted = 0 AND Resolution = 'FifteenMinutes'
),
sma_total AS (
    SELECT CAST(DeviceId AS nvarchar(200)) AS DeviceKey,
           CAST([Time] AS date)            AS Fecha,
           SUM(PvGeneration) / 1000.0      AS KwhDia
    FROM dw.factSmaPower15Minutes
    WHERE IsDeleted = 0 AND Resolution = 'OneDay'
    GROUP BY DeviceId, CAST([Time] AS date)
),
sma_dia AS (
    SELECT DeviceKey,
           CAST(Inicio AS date) AS Fecha,
           SUM(Kwh)             AS Kwh,
           SUM(CASE WHEN Kwh < 0 THEN 1 ELSE 0 END) AS Negativos,
           SUM(CASE WHEN Kwh > 0 AND (DATEPART(HOUR, Inicio) < 5 OR DATEPART(HOUR, Inicio) >= 19)
                    THEN Kwh ELSE 0 END)            AS KwhNoche
    FROM sma
    GROUP BY DeviceKey, CAST(Inicio AS date)
),
sma_calidad AS (
    SELECT d.DeviceKey, d.Fecha,
           CASE WHEN d.Negativos > 0   THEN 'INTERVALOS_NEGATIVOS'
                WHEN d.KwhNoche > 0.1  THEN 'GENERACION_NOCTURNA'
                WHEN t.KwhDia IS NULL  THEN 'SIN_TOTAL_DIARIO'
                WHEN ABS(t.KwhDia - d.Kwh) > 0.02 * t.KwhDia + 0.1 THEN 'NO_CUADRA_TOTAL_DIARIO'
           END AS Motivo
    FROM sma_dia d
    LEFT JOIN sma_total t ON t.DeviceKey = d.DeviceKey AND t.Fecha = d.Fecha
),
sma_hora AS (
    SELECT DeviceKey,
           CAST(Inicio AS date)   AS Fecha,
           DATEPART(HOUR, Inicio) AS Hora,
           SUM(Kwh)               AS Kwh,
           COUNT(*)               AS Lecturas
    FROM sma
    GROUP BY DeviceKey, CAST(Inicio AS date), DATEPART(HOUR, Inicio)
),
acum AS (
    SELECT CAST('growatt' AS varchar(20))  AS Proveedor,
           CAST(DeviceId AS nvarchar(200)) AS DeviceKey,
           [Time]                          AS Momento,
           EacToday                        AS Acumulado
    FROM dw.factGrowattEnergyAndPowerPv
    WHERE IsDeleted = 0
    UNION ALL
    SELECT 'soliscloud', CAST(DeviceId AS nvarchar(200)), DATEADD(HOUR, -6, [Time]), EToday
    FROM dw.factSoliscloudEnergyAndPowerPv
    WHERE IsDeleted = 0
),
acum_vecinos AS (
    SELECT Proveedor, DeviceKey, Momento, Acumulado,
           LAG(Acumulado)  OVER (PARTITION BY Proveedor, DeviceKey, CAST(Momento AS date) ORDER BY Momento) AS Anterior,
           LEAD(Acumulado) OVER (PARTITION BY Proveedor, DeviceKey, CAST(Momento AS date) ORDER BY Momento) AS Siguiente
    FROM acum
),
acum_lectura AS (
    -- Una lectura suelta mas baja que se recupera en la siguiente no afecta (maximo corrido). Si no se
    -- recupera (ej. el dia arranca con el acumulado de ayer y luego vuelve a 0), el dia queda REVISAR.
    SELECT Proveedor, DeviceKey,
           CAST(Momento AS date)   AS Fecha,
           DATEPART(HOUR, Momento) AS Hora,
           Acumulado,
           CASE WHEN Acumulado < Anterior AND (Siguiente IS NULL OR Siguiente < Anterior)
                THEN 1 ELSE 0 END  AS Baja
    FROM acum_vecinos
),
acum_hora AS (
    SELECT Proveedor, DeviceKey, Fecha, Hora,
           MAX(Acumulado) AS MaxHora,
           COUNT(*)       AS Lecturas,
           SUM(Baja)      AS Bajas
    FROM acum_lectura
    GROUP BY Proveedor, DeviceKey, Fecha, Hora
),
acum_corrido AS (
    SELECT Proveedor, DeviceKey, Fecha, Hora, Lecturas,
           MAX(MaxHora) OVER (PARTITION BY Proveedor, DeviceKey, Fecha ORDER BY Hora
                              ROWS UNBOUNDED PRECEDING)                   AS AcumHasta,
           SUM(Bajas)   OVER (PARTITION BY Proveedor, DeviceKey, Fecha)   AS BajasDia
    FROM acum_hora
),
hora AS (
    SELECT CAST('sma' AS varchar(20)) AS Proveedor, h.DeviceKey, h.Fecha, h.Hora, h.Kwh, h.Lecturas, c.Motivo
    FROM sma_hora h
    JOIN sma_calidad c ON c.DeviceKey = h.DeviceKey AND c.Fecha = h.Fecha
    UNION ALL
    SELECT Proveedor, DeviceKey, Fecha, Hora,
           AcumHasta - ISNULL(LAG(AcumHasta) OVER (PARTITION BY Proveedor, DeviceKey, Fecha ORDER BY Hora), 0),
           Lecturas,
           CASE WHEN BajasDia > 0 THEN 'ACUMULADO_BAJA' END
    FROM acum_corrido
)
SELECT
    i.Planta,
    CAST(pl.Plantel AS nvarchar(30))                         AS Plantel,
    i.InversorId,
    h.Proveedor,
    i.DeviceKey,
    i.EnReporte,
    h.Fecha,
    h.Hora,
    DATEADD(HOUR, h.Hora, CAST(h.Fecha AS datetime2(0)))     AS FechaHora,
    CAST(h.Kwh AS decimal(12,3))                             AS EnergiaKwh,
    h.Lecturas,
    CAST(CASE WHEN h.Motivo IS NULL THEN 'OK' ELSE 'REVISAR' END AS varchar(10)) AS CalidadDia,
    CAST(h.Motivo AS varchar(30))                            AS MotivoCalidad
FROM hora h
JOIN dw.vwRptInversor i
  ON i.Proveedor = h.Proveedor
 AND i.DeviceKey = h.DeviceKey COLLATE DATABASE_DEFAULT
JOIN dw.dimPlantaSolar pl
  ON pl.Planta = i.Planta AND pl.EsVigente = 1;
GO

-- Una fila por planta, fecha y hora (suma de sus inversores con dato en esa hora).
CREATE OR ALTER VIEW dw.vwSolarPlantaHora AS
SELECT
    Planta,
    Plantel,
    EnReporte,
    Fecha,
    Hora,
    FechaHora,
    SUM(EnergiaKwh)                                          AS EnergiaKwh,
    COUNT(*)                                                 AS InversoresConDato,
    SUM(CASE WHEN CalidadDia = 'REVISAR' THEN 1 ELSE 0 END)  AS InversoresRevisar
FROM dw.vwSolarInversorHora
GROUP BY Planta, Plantel, EnReporte, Fecha, Hora, FechaHora;
GO

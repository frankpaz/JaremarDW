-- 263: dw.vwDailyGenerationSummary agrupa Soliscloud por dia LOCAL (UTC-6), no por fecha UTC.
-- La hora de factSoliscloudEnergyAndPowerPv viene en UTC y EToday es el acumulado del dia local. Al
-- agrupar por fecha UTC, cada dia tomaba tambien las lecturas de 18:00 a 23:59 locales del dia anterior
-- (con su total final) y MAX(EToday) devolvia el total de ayer cuando ayer fue mejor: al 2026-10-06,
-- 61 de 136 dias-inversor de SOLIS inflados (+8.844 kWh, +12,8 %; ej. 14/08 ...0022: 23 kWh -> 809,9).
-- SMA, Growatt y Huawei quedan igual (copia de la 251).
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
    CAST(DATEADD(HOUR, -6, [Time]) AS date) AS GenerationDate,   -- [Time] viene en UTC
    MAX(EToday)                 AS EnergyKwh,
    MAX(GridSellTodayEnergy)    AS GridSellKwh,
    MAX(GridPurchasedTodayEnergy) AS GridPurchaseKwh
FROM dw.factSoliscloudEnergyAndPowerPv
GROUP BY
	DeviceId,
	CAST(DATEADD(HOUR, -6, [Time]) AS date);
GO

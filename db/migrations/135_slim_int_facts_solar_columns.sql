-- 135: recorta [int] de los hechos Solar a las columnas que consumen las
-- vistas de analisis (vwDailyGenerationSummary, vwDailyPerformance,
-- vwMeteoDailyRealVsPlan). stg conserva todo el detalle crudo; Silver solo
-- lleva lo necesario. Si mas adelante se requiere otro campo, se agrega con
-- una migracion nueva.
--
-- Se dropea toda columna que no este en la lista de conservadas de cada
-- tabla (idempotente: si ya se recorto, no hay nada que dropear). Las
-- columnas conservadas incluyen las de control (CreationTime,
-- LastModificationTime, IsDeleted, HashDiff, FechaCargaInt, RunId).

DECLARE @Sql NVARCHAR(MAX);

-- factSmaPower15Minutes: DeviceId, Time, Resolution, PvGeneration
SET @Sql = (
    SELECT 'ALTER TABLE [int].factSmaPower15Minutes DROP COLUMN ' + QUOTENAME(c.name) + ';'
    FROM sys.columns c
    WHERE c.object_id = OBJECT_ID('[int].factSmaPower15Minutes')
      AND c.name NOT IN ('Id','DeviceId','Resolution','Time','PvGeneration',
                         'CreationTime','LastModificationTime','IsDeleted','HashDiff','FechaCargaInt','RunId')
    FOR XML PATH(''), TYPE
).value('.', 'NVARCHAR(MAX)');
IF @Sql IS NOT NULL EXEC sp_executesql @Sql;

-- factHuaweiEnergyAndPowerPv: DeviceId, Time, ProductPower (KpiData.product_power)
SET @Sql = (
    SELECT 'ALTER TABLE [int].factHuaweiEnergyAndPowerPv DROP COLUMN ' + QUOTENAME(c.name) + ';'
    FROM sys.columns c
    WHERE c.object_id = OBJECT_ID('[int].factHuaweiEnergyAndPowerPv')
      AND c.name NOT IN ('Id','DeviceId','Time','ProductPower',
                         'CreationTime','LastModificationTime','IsDeleted','HashDiff','FechaCargaInt','RunId')
    FOR XML PATH(''), TYPE
).value('.', 'NVARCHAR(MAX)');
IF @Sql IS NOT NULL EXEC sp_executesql @Sql;

-- factSoliscloudEnergyAndPowerPv: DeviceId, Time, EToday, GridSellTodayEnergy, GridPurchasedTodayEnergy
SET @Sql = (
    SELECT 'ALTER TABLE [int].factSoliscloudEnergyAndPowerPv DROP COLUMN ' + QUOTENAME(c.name) + ';'
    FROM sys.columns c
    WHERE c.object_id = OBJECT_ID('[int].factSoliscloudEnergyAndPowerPv')
      AND c.name NOT IN ('Id','DeviceId','Time','EToday','GridSellTodayEnergy','GridPurchasedTodayEnergy',
                         'CreationTime','LastModificationTime','IsDeleted','HashDiff','FechaCargaInt','RunId')
    FOR XML PATH(''), TYPE
).value('.', 'NVARCHAR(MAX)');
IF @Sql IS NOT NULL EXEC sp_executesql @Sql;

-- factGrowattEnergyAndPowerPv: DeviceId, Time, EacToday
SET @Sql = (
    SELECT 'ALTER TABLE [int].factGrowattEnergyAndPowerPv DROP COLUMN ' + QUOTENAME(c.name) + ';'
    FROM sys.columns c
    WHERE c.object_id = OBJECT_ID('[int].factGrowattEnergyAndPowerPv')
      AND c.name NOT IN ('Id','DeviceId','Time','EacToday',
                         'CreationTime','LastModificationTime','IsDeleted','HashDiff','FechaCargaInt','RunId')
    FOR XML PATH(''), TYPE
).value('.', 'NVARCHAR(MAX)');
IF @Sql IS NOT NULL EXEC sp_executesql @Sql;

-- factMeteoDaily: Site, MeasuredDate, GhiRealWhM2, HsfRealHrs, WindSpeedRealMps, Source, RetrievedAt
SET @Sql = (
    SELECT 'ALTER TABLE [int].factMeteoDaily DROP COLUMN ' + QUOTENAME(c.name) + ';'
    FROM sys.columns c
    WHERE c.object_id = OBJECT_ID('[int].factMeteoDaily')
      AND c.name NOT IN ('Site','MeasuredDate','GhiRealWhM2','HsfRealHrs','WindSpeedRealMps','Source','RetrievedAt',
                         'EsVigente','HashDiff','FechaCargaInt','RunId')
    FOR XML PATH(''), TYPE
).value('.', 'NVARCHAR(MAX)');
IF @Sql IS NOT NULL EXEC sp_executesql @Sql;
GO

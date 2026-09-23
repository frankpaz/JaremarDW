-- 137: recorta dw de los hechos Solar a las columnas que consumen las
-- vistas de analisis (ver 135). Conserva las llaves subrogadas de
-- dispositivo (SmaDeviceKey, HuaweiDeviceKey, SoliscloudDeviceKey) y las
-- columnas de control. Idempotente.

-- El indice sobre SmaPlantaKey depende de una columna que se dropea.
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_dw_factSmaPower15Minutes_SmaPlantaKey'
           AND object_id = OBJECT_ID('dw.factSmaPower15Minutes'))
    DROP INDEX IX_dw_factSmaPower15Minutes_SmaPlantaKey ON dw.factSmaPower15Minutes;
GO

DECLARE @Sql NVARCHAR(MAX);

-- factSmaPower15Minutes
SET @Sql = (
    SELECT 'ALTER TABLE dw.factSmaPower15Minutes DROP COLUMN ' + QUOTENAME(c.name) + ';'
    FROM sys.columns c
    WHERE c.object_id = OBJECT_ID('dw.factSmaPower15Minutes')
      AND c.name NOT IN ('Id','SmaDeviceKey','DeviceId','Resolution','Time','PvGeneration',
                         'CreationTime','LastModificationTime','IsDeleted','HashDiff','FechaCargaDw','RunId')
    FOR XML PATH(''), TYPE
).value('.', 'NVARCHAR(MAX)');
IF @Sql IS NOT NULL EXEC sp_executesql @Sql;

-- factHuaweiEnergyAndPowerPv
SET @Sql = (
    SELECT 'ALTER TABLE dw.factHuaweiEnergyAndPowerPv DROP COLUMN ' + QUOTENAME(c.name) + ';'
    FROM sys.columns c
    WHERE c.object_id = OBJECT_ID('dw.factHuaweiEnergyAndPowerPv')
      AND c.name NOT IN ('Id','HuaweiDeviceKey','DeviceId','Time','ProductPower',
                         'CreationTime','LastModificationTime','IsDeleted','HashDiff','FechaCargaDw','RunId')
    FOR XML PATH(''), TYPE
).value('.', 'NVARCHAR(MAX)');
IF @Sql IS NOT NULL EXEC sp_executesql @Sql;

-- factSoliscloudEnergyAndPowerPv
SET @Sql = (
    SELECT 'ALTER TABLE dw.factSoliscloudEnergyAndPowerPv DROP COLUMN ' + QUOTENAME(c.name) + ';'
    FROM sys.columns c
    WHERE c.object_id = OBJECT_ID('dw.factSoliscloudEnergyAndPowerPv')
      AND c.name NOT IN ('Id','SoliscloudDeviceKey','DeviceId','Time','EToday','GridSellTodayEnergy','GridPurchasedTodayEnergy',
                         'CreationTime','LastModificationTime','IsDeleted','HashDiff','FechaCargaDw','RunId')
    FOR XML PATH(''), TYPE
).value('.', 'NVARCHAR(MAX)');
IF @Sql IS NOT NULL EXEC sp_executesql @Sql;

-- factGrowattEnergyAndPowerPv
SET @Sql = (
    SELECT 'ALTER TABLE dw.factGrowattEnergyAndPowerPv DROP COLUMN ' + QUOTENAME(c.name) + ';'
    FROM sys.columns c
    WHERE c.object_id = OBJECT_ID('dw.factGrowattEnergyAndPowerPv')
      AND c.name NOT IN ('Id','DeviceId','Time','EacToday',
                         'CreationTime','LastModificationTime','IsDeleted','HashDiff','FechaCargaDw','RunId')
    FOR XML PATH(''), TYPE
).value('.', 'NVARCHAR(MAX)');
IF @Sql IS NOT NULL EXEC sp_executesql @Sql;

-- factMeteoDaily
SET @Sql = (
    SELECT 'ALTER TABLE dw.factMeteoDaily DROP COLUMN ' + QUOTENAME(c.name) + ';'
    FROM sys.columns c
    WHERE c.object_id = OBJECT_ID('dw.factMeteoDaily')
      AND c.name NOT IN ('MeteoDailyKey','Site','MeasuredDate','GhiRealWhM2','HsfRealHrs','WindSpeedRealMps','Source','RetrievedAt',
                         'EsVigente','HashDiff','FechaCargaDw','RunId')
    FOR XML PATH(''), TYPE
).value('.', 'NVARCHAR(MAX)');
IF @Sql IS NOT NULL EXEC sp_executesql @Sql;
GO

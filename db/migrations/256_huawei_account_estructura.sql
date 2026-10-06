-- 256: Huawei guarda la cuenta del portal (Account). Estructura; los procedimientos van en la 257.
--
-- El 2026-10-05 el proceso externo agrego Account a stg.dimHuaweiStations, stg.dimHuaweiDevices y
-- stg.factHuaweiEnergyAndPowerPv: 'edif-admin' (la estacion que ya habia) y 'san-alejo' (estacion
-- nueva "Jaremar San Alejo", NE=59869602, 6 inversores). Se guarda en [int] y dw para saber de que
-- cuenta viene cada equipo.
--
-- * stg: la columna la crea el proceso externo; aqui solo se agrega si falta (bases de desarrollo
--   donde el proceso externo no corre), para que los procedimientos de la 257 compilen.
-- * El hecho es incremental: las filas ya cargadas se completan desde stg por Id. Las dimensiones
--   son FULL y se completan en la siguiente corrida.

IF COL_LENGTH('stg.dimHuaweiStations', 'Account') IS NULL
    ALTER TABLE stg.dimHuaweiStations ADD Account NVARCHAR(50) NULL;
IF COL_LENGTH('stg.dimHuaweiDevices', 'Account') IS NULL
    ALTER TABLE stg.dimHuaweiDevices ADD Account NVARCHAR(50) NULL;
IF COL_LENGTH('stg.factHuaweiEnergyAndPowerPv', 'Account') IS NULL
    ALTER TABLE stg.factHuaweiEnergyAndPowerPv ADD Account NVARCHAR(50) NULL;

IF COL_LENGTH('[int].dimHuaweiStations', 'Account') IS NULL
    ALTER TABLE [int].dimHuaweiStations ADD Account NVARCHAR(50) NULL;
IF COL_LENGTH('dw.dimHuaweiStations', 'Account') IS NULL
    ALTER TABLE dw.dimHuaweiStations ADD Account NVARCHAR(50) NULL;

IF COL_LENGTH('[int].dimHuaweiDevices', 'Account') IS NULL
    ALTER TABLE [int].dimHuaweiDevices ADD Account NVARCHAR(50) NULL;
IF COL_LENGTH('dw.dimHuaweiDevices', 'Account') IS NULL
    ALTER TABLE dw.dimHuaweiDevices ADD Account NVARCHAR(50) NULL;

IF COL_LENGTH('[int].factHuaweiEnergyAndPowerPv', 'Account') IS NULL
    ALTER TABLE [int].factHuaweiEnergyAndPowerPv ADD Account NVARCHAR(50) NULL;
IF COL_LENGTH('dw.factHuaweiEnergyAndPowerPv', 'Account') IS NULL
    ALTER TABLE dw.factHuaweiEnergyAndPowerPv ADD Account NVARCHAR(50) NULL;
GO

-- Relleno del hecho ya cargado (no toca HashDiff: si la fila vuelve a llegar se actualiza sola).
UPDATE i
SET Account = NULLIF(RTRIM(s.Account), '')
FROM [int].factHuaweiEnergyAndPowerPv i
JOIN stg.factHuaweiEnergyAndPowerPv s ON s.Id = i.Id
WHERE i.Account IS NULL AND NULLIF(RTRIM(s.Account), '') IS NOT NULL;

UPDATE d
SET Account = i.Account
FROM dw.factHuaweiEnergyAndPowerPv d
JOIN [int].factHuaweiEnergyAndPowerPv i ON i.Id = d.Id
WHERE d.Account IS NULL AND i.Account IS NOT NULL;
GO

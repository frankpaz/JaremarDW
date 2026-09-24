-- 157: merge Silver -> Gold del plan de generacion, con las columnas nuevas (155) y la
-- resolucion del dispositivo POR FABRICANTE a partir de Proveedor + DispositivoId (la
-- columna 'Inversor' del archivo). Cada fabricante se enlaza con su dimension:
--   sma         dw.dimSmaDevices.DeviceId          -> SmaDeviceKey
--   huawei      dw.dimHuaweiDevices.DeviceId       -> HuaweiDeviceKey
--   soliscloud  dw.dimSoliscloudDevices.DeviceSn   -> SoliscloudDeviceKey
--   growatt     dw.dimDeviceCapacity.JoinKey       -> DeviceCapacityKey
-- Para cualquier fabricante, DeviceCapacityKey tambien se resuelve por
-- dimDeviceCapacity.InverterId = CodigoInversor (como hasta ahora; el reporte lo usa).
-- Respaldo para filas sin DispositivoId (version anterior del plan): por nombre del
-- dispositivo SMA ('HARINA-1 (SN ...)') y por SerialInversor cuando es unico.
-- Si no resuelve, las llaves quedan NULL; una corrida posterior las rellena cuando
-- la dimension exista (MATCHED compara tambien las llaves).
-- IMPORTANTE: PlanDiarioAsignado es el plan de la PLANTA y se repite en cada inversor
-- de la planta; para el plan por planta usar MAX por (Planta, Fecha), no SUM.

CREATE OR ALTER PROCEDURE dw.usp_MergeDimPlanGeneracion
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].dimPlanGeneracion);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH SmaPorId AS (
        SELECT CAST(DeviceId AS NVARCHAR(50)) AS DispositivoId, SmaDeviceKey,
               ROW_NUMBER() OVER (PARTITION BY DeviceId ORDER BY EsVigente DESC, SmaDeviceKey) AS rn
        FROM dw.dimSmaDevices
    ),
    HuaweiPorId AS (
        SELECT CAST(DeviceId AS NVARCHAR(50)) AS DispositivoId, HuaweiDeviceKey,
               ROW_NUMBER() OVER (PARTITION BY DeviceId ORDER BY EsVigente DESC, HuaweiDeviceKey) AS rn
        FROM dw.dimHuaweiDevices
    ),
    SolisPorSn AS (
        SELECT DeviceSn AS DispositivoId, SoliscloudDeviceKey,
               ROW_NUMBER() OVER (PARTITION BY DeviceSn ORDER BY EsVigente DESC, SoliscloudDeviceKey) AS rn
        FROM dw.dimSoliscloudDevices
        WHERE DeviceSn IS NOT NULL
    ),
    CapacidadPorSn AS (
        SELECT JoinKey, DeviceCapacityKey,
               ROW_NUMBER() OVER (PARTITION BY JoinKey ORDER BY EsVigente DESC, DeviceCapacityKey) AS rn
        FROM dw.dimDeviceCapacity
        WHERE JoinKey IS NOT NULL
    ),
    Dispositivos AS (
        SELECT SmaDeviceKey,
               LEFT(DeviceName, CHARINDEX(' (SN', DeviceName + ' (SN') - 1) AS CodigoInversor,
               ROW_NUMBER() OVER (PARTITION BY LEFT(DeviceName, CHARINDEX(' (SN', DeviceName + ' (SN') - 1)
                                  ORDER BY EsVigente DESC, SmaDeviceKey) AS rn
        FROM dw.dimSmaDevices
        WHERE DeviceName IS NOT NULL
    ),
    PorSerial AS (
        SELECT Serial, MIN(SmaDeviceKey) AS SmaDeviceKey
        FROM dw.dimSmaDevices
        WHERE Serial IS NOT NULL
        GROUP BY Serial
        HAVING COUNT(*) = 1
    ),
    Capacidad AS (
        SELECT DeviceCapacityKey, InverterId,
               ROW_NUMBER() OVER (PARTITION BY InverterId ORDER BY EsVigente DESC, DeviceCapacityKey) AS rn
        FROM dw.dimDeviceCapacity
    ),
    Origen AS (
        SELECT i.Fecha, i.CodigoInversor, i.PlanVersion, i.PlanKwh, i.PlanFuente, i.ArchivoOrigen,
               i.Planta, i.Proveedor, i.DispositivoId, i.Ubicacion, i.Mes, i.NombreMes, i.PlanDiarioAsignado,
               i.EsVigente, i.HashDiff,
               COALESCE(CASE WHEN i.Proveedor = 'sma' THEN sm.SmaDeviceKey END, d.SmaDeviceKey, s.SmaDeviceKey) AS SmaDeviceKey,
               CASE WHEN i.Proveedor = 'huawei' THEN hw.HuaweiDeviceKey END                                   AS HuaweiDeviceKey,
               CASE WHEN i.Proveedor = 'soliscloud' THEN so.SoliscloudDeviceKey END                           AS SoliscloudDeviceKey,
               COALESCE(c.DeviceCapacityKey, cs.DeviceCapacityKey)                                            AS DeviceCapacityKey
        FROM [int].dimPlanGeneracion i
        LEFT JOIN SmaPorId sm      ON sm.DispositivoId = i.DispositivoId AND sm.rn = 1
        LEFT JOIN HuaweiPorId hw   ON hw.DispositivoId = i.DispositivoId AND hw.rn = 1
        LEFT JOIN SolisPorSn so    ON so.DispositivoId = i.DispositivoId AND so.rn = 1
        LEFT JOIN CapacidadPorSn cs ON cs.JoinKey = i.DispositivoId AND cs.rn = 1
        LEFT JOIN Dispositivos d   ON d.CodigoInversor = i.CodigoInversor AND d.rn = 1
        LEFT JOIN PorSerial s      ON s.Serial = i.SerialInversor
        LEFT JOIN Capacidad c      ON c.InverterId = i.CodigoInversor AND c.rn = 1
    )
    MERGE dw.dimPlanGeneracion AS destino
        USING Origen AS origen
        ON destino.Fecha = origen.Fecha AND destino.CodigoInversor = origen.CodigoInversor
           AND destino.PlanVersion = origen.PlanVersion
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff
                      OR destino.EsVigente <> origen.EsVigente
                      OR ISNULL(destino.SmaDeviceKey, -1) <> ISNULL(origen.SmaDeviceKey, -1)
                      OR ISNULL(destino.HuaweiDeviceKey, -1) <> ISNULL(origen.HuaweiDeviceKey, -1)
                      OR ISNULL(destino.SoliscloudDeviceKey, -1) <> ISNULL(origen.SoliscloudDeviceKey, -1)
                      OR ISNULL(destino.DeviceCapacityKey, -1) <> ISNULL(origen.DeviceCapacityKey, -1)) THEN
        UPDATE SET
            SmaDeviceKey        = origen.SmaDeviceKey,
            HuaweiDeviceKey     = origen.HuaweiDeviceKey,
            SoliscloudDeviceKey = origen.SoliscloudDeviceKey,
            DeviceCapacityKey   = origen.DeviceCapacityKey,
            Planta              = origen.Planta,
            Proveedor           = origen.Proveedor,
            DispositivoId       = origen.DispositivoId,
            Ubicacion           = origen.Ubicacion,
            Mes                 = origen.Mes,
            NombreMes           = origen.NombreMes,
            PlanDiarioAsignado  = origen.PlanDiarioAsignado,
            PlanKwh             = origen.PlanKwh,
            PlanFuente          = origen.PlanFuente,
            ArchivoOrigen       = origen.ArchivoOrigen,
            EsVigente           = origen.EsVigente,
            HashDiff            = origen.HashDiff,
            FechaCargaDw        = SYSDATETIME(),
            RunId               = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (Fecha, CodigoInversor, SmaDeviceKey, HuaweiDeviceKey, SoliscloudDeviceKey, DeviceCapacityKey,
                Planta, Proveedor, DispositivoId, Ubicacion, Mes, NombreMes, PlanDiarioAsignado,
                PlanKwh, PlanVersion, PlanFuente, ArchivoOrigen, EsVigente, HashDiff, RunId)
        VALUES (origen.Fecha, origen.CodigoInversor, origen.SmaDeviceKey, origen.HuaweiDeviceKey, origen.SoliscloudDeviceKey,
                origen.DeviceCapacityKey, origen.Planta, origen.Proveedor, origen.DispositivoId, origen.Ubicacion,
                origen.Mes, origen.NombreMes, origen.PlanDiarioAsignado, origen.PlanKwh, origen.PlanVersion,
                origen.PlanFuente, origen.ArchivoOrigen, origen.EsVigente, origen.HashDiff, @RunId)
    OUTPUT $action INTO #AccionesMerge;

    SELECT
        @FilasLeidas                                                                 AS FilasLeidas,
        ISNULL(SUM(CASE WHEN Accion = 'INSERT' THEN 1 ELSE 0 END), 0)                AS FilasInsertadas,
        ISNULL(SUM(CASE WHEN Accion = 'UPDATE' THEN 1 ELSE 0 END), 0)                AS FilasActualizadas,
        @FilasLeidas - ISNULL(SUM(CASE WHEN Accion = 'INSERT' THEN 1 ELSE 0 END), 0)
                      - ISNULL(SUM(CASE WHEN Accion = 'UPDATE' THEN 1 ELSE 0 END), 0) AS FilasIgnoradas
    FROM #AccionesMerge;
END
GO

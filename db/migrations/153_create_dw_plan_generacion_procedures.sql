-- 153: merge Silver -> Gold del plan de generacion de energia. SCD Tipo 1
-- (sobrescribe); reutiliza el HashDiff de [int]. El historial de versiones se
-- conserva: solo cambia EsVigente.
--
-- Resolucion del inversor contra las dimensiones de dispositivos:
--   * SMA: dw.dimSmaDevices.DeviceName trae el ID del inversor antes de ' (SN',
--     ej. 'HARINA-1 (SN 3009155068)'. Se compara por ese ID y NO por el serial,
--     porque hay seriales SMA repetidos en dos plantas (uno con nombre y otro
--     solo 'SN ...').
--     Respaldo: si el portal no le puso el ID al dispositivo (ej. JABON-2 aparece
--     solo como 'SN 3006256658'), se enlaza por SerialInversor (de la hoja
--     'Inversores' del Excel) solo cuando ese serial identifica UN unico dispositivo.
--   * Otros fabricantes: dw.dimDeviceCapacity.InverterId (ej. 'DETERGENTE-1').
-- Si el ID no resuelve, las llaves quedan NULL. Cuando una dimension se cargue
-- despues, la siguiente corrida rellena la llave (la condicion de MATCHED
-- compara tambien las llaves, no solo el HashDiff).

CREATE OR ALTER PROCEDURE dw.usp_MergeDimPlanGeneracion
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].dimPlanGeneracion);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH Dispositivos AS (
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
               i.EsVigente, i.HashDiff,
               COALESCE(d.SmaDeviceKey, s.SmaDeviceKey) AS SmaDeviceKey, c.DeviceCapacityKey
        FROM [int].dimPlanGeneracion i
        LEFT JOIN Dispositivos d ON d.CodigoInversor = i.CodigoInversor AND d.rn = 1
        LEFT JOIN PorSerial s ON s.Serial = i.SerialInversor
        LEFT JOIN Capacidad c ON c.InverterId = i.CodigoInversor AND c.rn = 1
    )
    MERGE dw.dimPlanGeneracion AS destino
        USING Origen AS origen
        ON destino.Fecha = origen.Fecha AND destino.CodigoInversor = origen.CodigoInversor
           AND destino.PlanVersion = origen.PlanVersion
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff
                      OR destino.EsVigente <> origen.EsVigente
                      OR ISNULL(destino.SmaDeviceKey, -1) <> ISNULL(origen.SmaDeviceKey, -1)
                      OR ISNULL(destino.DeviceCapacityKey, -1) <> ISNULL(origen.DeviceCapacityKey, -1)) THEN
        UPDATE SET
            SmaDeviceKey       = origen.SmaDeviceKey,
            DeviceCapacityKey  = origen.DeviceCapacityKey,
            PlanKwh            = origen.PlanKwh,
            PlanFuente         = origen.PlanFuente,
            ArchivoOrigen      = origen.ArchivoOrigen,
            EsVigente          = origen.EsVigente,
            HashDiff           = origen.HashDiff,
            FechaCargaDw       = SYSDATETIME(),
            RunId              = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (Fecha, CodigoInversor, SmaDeviceKey, DeviceCapacityKey, PlanKwh, PlanVersion, PlanFuente,
                ArchivoOrigen, EsVigente, HashDiff, RunId)
        VALUES (origen.Fecha, origen.CodigoInversor, origen.SmaDeviceKey, origen.DeviceCapacityKey, origen.PlanKwh,
                origen.PlanVersion, origen.PlanFuente, origen.ArchivoOrigen, origen.EsVigente, origen.HashDiff, @RunId)
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

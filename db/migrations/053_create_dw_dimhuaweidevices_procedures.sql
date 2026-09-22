-- 053: merge Silver -> Gold para dimHuaweiDevices. SCD Tipo 1 (sobrescribe).
-- Resuelve HuaweiStationKey por StationCode contra dw.dimHuaweiStations
-- (debe cargarse primero).

CREATE OR ALTER PROCEDURE dw.usp_MergeDimHuaweiDevices
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH Origen AS (
        SELECT
            st.HuaweiStationKey,
            d.StationCode,
            d.DeviceId,
            d.DeviceEsn,
            d.DeviceName,
            d.DeviceTypeId,
            d.Model,
            d.SoftwareVersion,
            d.OptimizerNumber,
            d.InvType,
            d.Longitude,
            d.Latitude,
            d.IsGenerator,
            d.EsVigente,
            d.HashDiff
        FROM [int].dimHuaweiDevices d
        JOIN dw.dimHuaweiStations st ON st.StationCode = d.StationCode
    )
    SELECT * INTO #Origen FROM Origen;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM #Origen);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    MERGE dw.dimHuaweiDevices AS destino
        USING #Origen AS origen
        ON destino.DeviceId = origen.DeviceId
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente) THEN
        UPDATE SET
            HuaweiStationKey  = origen.HuaweiStationKey,
            StationCode       = origen.StationCode,
            DeviceEsn         = origen.DeviceEsn,
            DeviceName        = origen.DeviceName,
            DeviceTypeId      = origen.DeviceTypeId,
            Model             = origen.Model,
            SoftwareVersion   = origen.SoftwareVersion,
            OptimizerNumber   = origen.OptimizerNumber,
            InvType           = origen.InvType,
            Longitude         = origen.Longitude,
            Latitude          = origen.Latitude,
            IsGenerator       = origen.IsGenerator,
            EsVigente         = origen.EsVigente,
            HashDiff          = origen.HashDiff,
            FechaCargaDw      = SYSDATETIME(),
            RunId             = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (
            HuaweiStationKey, StationCode, DeviceId, DeviceEsn, DeviceName, DeviceTypeId, Model,
            SoftwareVersion, OptimizerNumber, InvType, Longitude, Latitude, IsGenerator, EsVigente, HashDiff, RunId
        )
        VALUES (
            origen.HuaweiStationKey, origen.StationCode, origen.DeviceId, origen.DeviceEsn, origen.DeviceName,
            origen.DeviceTypeId, origen.Model, origen.SoftwareVersion, origen.OptimizerNumber, origen.InvType,
            origen.Longitude, origen.Latitude, origen.IsGenerator, origen.EsVigente, origen.HashDiff, @RunId
        )
    OUTPUT $action INTO #AccionesMerge;

    SELECT
        @FilasLeidas                                                                 AS FilasLeidas,
        ISNULL(SUM(CASE WHEN Accion = 'INSERT' THEN 1 ELSE 0 END), 0)                AS FilasInsertadas,
        ISNULL(SUM(CASE WHEN Accion = 'UPDATE' THEN 1 ELSE 0 END), 0)                AS FilasActualizadas,
        @FilasLeidas - ISNULL(SUM(CASE WHEN Accion = 'INSERT' THEN 1 ELSE 0 END), 0)
                      - ISNULL(SUM(CASE WHEN Accion = 'UPDATE' THEN 1 ELSE 0 END), 0) AS FilasIgnoradas
    FROM #AccionesMerge;

    DROP TABLE #Origen;
END
GO

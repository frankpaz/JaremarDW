-- 061: merge Silver -> Gold para dimSoliscloudDevices. SCD Tipo 1 (sobrescribe).
-- Resuelve SoliscloudStationKey por StationId contra dw.dimSoliscloudStations
-- (debe cargarse primero).

CREATE OR ALTER PROCEDURE dw.usp_MergeDimSoliscloudDevices
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH Origen AS (
        SELECT
            st.SoliscloudStationKey,
            d.StationId,
            d.DeviceId,
            d.DeviceSn,
            d.Model,
            d.ProductModel,
            d.CollectorSn,
            d.InverterSoftwareVersion,
            d.TimeZone,
            d.IsGenerator,
            d.EsVigente,
            d.HashDiff
        FROM [int].dimSoliscloudDevices d
        JOIN dw.dimSoliscloudStations st ON st.StationId = d.StationId
    )
    SELECT * INTO #Origen FROM Origen;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM #Origen);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    MERGE dw.dimSoliscloudDevices AS destino
        USING #Origen AS origen
        ON destino.DeviceId = origen.DeviceId
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente) THEN
        UPDATE SET
            SoliscloudStationKey     = origen.SoliscloudStationKey,
            StationId                = origen.StationId,
            DeviceSn                 = origen.DeviceSn,
            Model                    = origen.Model,
            ProductModel             = origen.ProductModel,
            CollectorSn              = origen.CollectorSn,
            InverterSoftwareVersion  = origen.InverterSoftwareVersion,
            TimeZone                 = origen.TimeZone,
            IsGenerator              = origen.IsGenerator,
            EsVigente                = origen.EsVigente,
            HashDiff                 = origen.HashDiff,
            FechaCargaDw             = SYSDATETIME(),
            RunId                    = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (
            SoliscloudStationKey, StationId, DeviceId, DeviceSn, Model, ProductModel, CollectorSn,
            InverterSoftwareVersion, TimeZone, IsGenerator, EsVigente, HashDiff, RunId
        )
        VALUES (
            origen.SoliscloudStationKey, origen.StationId, origen.DeviceId, origen.DeviceSn, origen.Model,
            origen.ProductModel, origen.CollectorSn, origen.InverterSoftwareVersion, origen.TimeZone,
            origen.IsGenerator, origen.EsVigente, origen.HashDiff, @RunId
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

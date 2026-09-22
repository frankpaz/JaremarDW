-- 059: merge Bronze -> Silver para dimSoliscloudDevices.

CREATE OR ALTER PROCEDURE [int].usp_MergeDimSoliscloudDevices
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.dimSoliscloudDevices);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH StgDeduplicado AS (
        SELECT s.*,
               ROW_NUMBER() OVER (PARTITION BY RTRIM(s.DeviceId) ORDER BY (SELECT NULL)) AS rn
        FROM stg.dimSoliscloudDevices s
        WHERE RTRIM(ISNULL(s.DeviceId, '')) <> '' AND RTRIM(ISNULL(s.StationId, '')) <> ''
    ),
    StgNormalizado AS (
        SELECT
            RTRIM(s.DeviceId)                                AS DeviceId,
            RTRIM(s.StationId)                                AS StationId,
            NULLIF(RTRIM(s.DeviceSn), '')                     AS DeviceSn,
            NULLIF(RTRIM(s.Model), '')                        AS Model,
            NULLIF(RTRIM(s.ProductModel), '')                 AS ProductModel,
            NULLIF(RTRIM(s.CollectorSn), '')                  AS CollectorSn,
            NULLIF(RTRIM(s.InverterSoftwareVersion), '')      AS InverterSoftwareVersion,
            s.TimeZone,
            s.IsGenerator
        FROM StgDeduplicado s
        WHERE s.rn = 1
    ),
    StgConHash AS (
        SELECT
            n.*,
            HASHBYTES('SHA2_256', (SELECT n.* FOR XML RAW, BINARY BASE64)) AS HashDiff
        FROM StgNormalizado n
    )
    MERGE [int].dimSoliscloudDevices AS destino
        USING StgConHash AS origen
        ON destino.DeviceId = origen.DeviceId
    WHEN MATCHED AND destino.HashDiff <> origen.HashDiff THEN
        UPDATE SET
            StationId                = origen.StationId,
            DeviceSn                 = origen.DeviceSn,
            Model                    = origen.Model,
            ProductModel             = origen.ProductModel,
            CollectorSn              = origen.CollectorSn,
            InverterSoftwareVersion  = origen.InverterSoftwareVersion,
            TimeZone                 = origen.TimeZone,
            IsGenerator              = origen.IsGenerator,
            EsVigente                = 1,
            HashDiff                 = origen.HashDiff,
            FechaCargaInt            = SYSDATETIME(),
            RunId                    = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (
            DeviceId, StationId, DeviceSn, Model, ProductModel, CollectorSn,
            InverterSoftwareVersion, TimeZone, IsGenerator, HashDiff, RunId
        )
        VALUES (
            origen.DeviceId, origen.StationId, origen.DeviceSn, origen.Model, origen.ProductModel,
            origen.CollectorSn, origen.InverterSoftwareVersion, origen.TimeZone, origen.IsGenerator,
            origen.HashDiff, @RunId
        )
    WHEN NOT MATCHED BY SOURCE AND destino.EsVigente = 1 THEN
        UPDATE SET EsVigente = 0, FechaCargaInt = SYSDATETIME(), RunId = @RunId
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

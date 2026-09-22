-- 051: merge Bronze -> Silver para dimHuaweiDevices.

CREATE OR ALTER PROCEDURE [int].usp_MergeDimHuaweiDevices
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.dimHuaweiDevices);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH StgDeduplicado AS (
        SELECT s.*,
               ROW_NUMBER() OVER (PARTITION BY RTRIM(s.DeviceId) ORDER BY (SELECT NULL)) AS rn
        FROM stg.dimHuaweiDevices s
        WHERE RTRIM(ISNULL(s.DeviceId, '')) <> '' AND RTRIM(ISNULL(s.StationCode, '')) <> ''
    ),
    StgNormalizado AS (
        SELECT
            RTRIM(s.DeviceId)                       AS DeviceId,
            RTRIM(s.StationCode)                    AS StationCode,
            NULLIF(RTRIM(s.DeviceEsn), '')          AS DeviceEsn,
            NULLIF(RTRIM(s.DeviceName), '')         AS DeviceName,
            s.DeviceTypeId,
            NULLIF(RTRIM(s.Model), '')              AS Model,
            NULLIF(RTRIM(s.SoftwareVersion), '')    AS SoftwareVersion,
            s.OptimizerNumber,
            NULLIF(RTRIM(s.InvType), '')            AS InvType,
            s.Longitude,
            s.Latitude,
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
    MERGE [int].dimHuaweiDevices AS destino
        USING StgConHash AS origen
        ON destino.DeviceId = origen.DeviceId
    WHEN MATCHED AND destino.HashDiff <> origen.HashDiff THEN
        UPDATE SET
            StationCode      = origen.StationCode,
            DeviceEsn        = origen.DeviceEsn,
            DeviceName       = origen.DeviceName,
            DeviceTypeId     = origen.DeviceTypeId,
            Model            = origen.Model,
            SoftwareVersion  = origen.SoftwareVersion,
            OptimizerNumber  = origen.OptimizerNumber,
            InvType          = origen.InvType,
            Longitude        = origen.Longitude,
            Latitude         = origen.Latitude,
            IsGenerator      = origen.IsGenerator,
            EsVigente        = 1,
            HashDiff         = origen.HashDiff,
            FechaCargaInt    = SYSDATETIME(),
            RunId            = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (
            DeviceId, StationCode, DeviceEsn, DeviceName, DeviceTypeId, Model,
            SoftwareVersion, OptimizerNumber, InvType, Longitude, Latitude, IsGenerator, HashDiff, RunId
        )
        VALUES (
            origen.DeviceId, origen.StationCode, origen.DeviceEsn, origen.DeviceName, origen.DeviceTypeId,
            origen.Model, origen.SoftwareVersion, origen.OptimizerNumber, origen.InvType, origen.Longitude,
            origen.Latitude, origen.IsGenerator, origen.HashDiff, @RunId
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

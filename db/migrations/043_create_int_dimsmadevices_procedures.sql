-- 043: merge Bronze -> Silver para dimSmaDevices.

CREATE OR ALTER PROCEDURE [int].usp_MergeDimSmaDevices
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.dimSmaDevices);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH StgDeduplicado AS (
        SELECT s.*,
               ROW_NUMBER() OVER (PARTITION BY s.DeviceId ORDER BY (SELECT NULL)) AS rn
        FROM stg.dimSmaDevices s
        WHERE s.DeviceId IS NOT NULL AND s.PlantId IS NOT NULL
    ),
    StgNormalizado AS (
        SELECT
            s.DeviceId,
            s.PlantId,
            NULLIF(RTRIM(s.DeviceName), '')       AS DeviceName,
            NULLIF(RTRIM(s.DeviceTimezone), '')   AS DeviceTimezone,
            NULLIF(RTRIM(s.DeviceType), '')       AS DeviceType,
            NULLIF(RTRIM(s.Product), '')          AS Product,
            s.ProductId,
            NULLIF(RTRIM(s.Serial), '')           AS Serial,
            NULLIF(RTRIM(s.Vendor), '')           AS Vendor,
            s.GeneratorPower,
            s.GeneratorPowerDc,
            s.IsActive,
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
    MERGE [int].dimSmaDevices AS destino
        USING StgConHash AS origen
        ON destino.DeviceId = origen.DeviceId
    WHEN MATCHED AND destino.HashDiff <> origen.HashDiff THEN
        UPDATE SET
            PlantId           = origen.PlantId,
            DeviceName        = origen.DeviceName,
            DeviceTimezone    = origen.DeviceTimezone,
            DeviceType        = origen.DeviceType,
            Product           = origen.Product,
            ProductId         = origen.ProductId,
            Serial            = origen.Serial,
            Vendor            = origen.Vendor,
            GeneratorPower    = origen.GeneratorPower,
            GeneratorPowerDc  = origen.GeneratorPowerDc,
            IsActive          = origen.IsActive,
            IsGenerator       = origen.IsGenerator,
            EsVigente         = 1,
            HashDiff          = origen.HashDiff,
            FechaCargaInt     = SYSDATETIME(),
            RunId             = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (
            DeviceId, PlantId, DeviceName, DeviceTimezone, DeviceType, Product, ProductId,
            Serial, Vendor, GeneratorPower, GeneratorPowerDc, IsActive, IsGenerator, HashDiff, RunId
        )
        VALUES (
            origen.DeviceId, origen.PlantId, origen.DeviceName, origen.DeviceTimezone, origen.DeviceType,
            origen.Product, origen.ProductId, origen.Serial, origen.Vendor, origen.GeneratorPower,
            origen.GeneratorPowerDc, origen.IsActive, origen.IsGenerator, origen.HashDiff, @RunId
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

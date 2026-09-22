-- 084: merge Bronze -> Silver para factHuaweiEnergyAndPowerPv. INCREMENTAL,
-- mismo patron de watermark (truncado a milisegundo) que los facts SMA.
-- Parsea KpiData (JSON) a columnas tipadas via JSON_VALUE.

CREATE OR ALTER PROCEDURE [int].usp_MergeFactHuaweiEnergyAndPowerPv
    @RunId            INT,
    @UltimoWatermark  DATETIME2(7) = NULL,
    @NuevoWatermark   DATETIME2(7) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Desde DATETIME2(3) = CONVERT(DATETIME2(3), ISNULL(@UltimoWatermark, '1900-01-01'));

    ;WITH StgIncremental AS (
        SELECT s.*
        FROM stg.factHuaweiEnergyAndPowerPv s
        WHERE CONVERT(DATETIME2(3), s.CreationTime) > @Desde
           OR CONVERT(DATETIME2(3), s.LastModificationTime) > @Desde
    ),
    StgDeduplicado AS (
        SELECT s.*,
               ROW_NUMBER() OVER (PARTITION BY s.Id ORDER BY (SELECT NULL)) AS rn
        FROM StgIncremental s
    ),
    StgNormalizado AS (
        SELECT
            s.Id,
            RTRIM(s.DeviceId)                                                  AS DeviceId,
            DATEADD(SECOND, s.Time / 1000, '1970-01-01')                       AS Time,
            TRY_CONVERT(DECIMAL(18,3), JSON_VALUE(s.KpiData, '$.installed_capacity')) AS InstalledCapacity,
            TRY_CONVERT(DECIMAL(18,4), JSON_VALUE(s.KpiData, '$.perpower_ratio'))     AS PerpowerRatio,
            TRY_CONVERT(DECIMAL(18,3), JSON_VALUE(s.KpiData, '$.product_power'))      AS ProductPower,
            s.KpiData                                                          AS KpiDataRaw,
            s.CreationTime,
            s.LastModificationTime,
            s.IsDeleted
        FROM StgDeduplicado s
        WHERE s.rn = 1
    ),
    StgConHash AS (
        SELECT
            n.*,
            HASHBYTES('SHA2_256', (SELECT n.* FOR XML RAW, BINARY BASE64)) AS HashDiff
        FROM StgNormalizado n
    )
    SELECT * INTO #Origen FROM StgConHash;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM #Origen);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    MERGE [int].factHuaweiEnergyAndPowerPv AS destino
        USING #Origen AS origen
        ON destino.Id = origen.Id
    WHEN MATCHED AND destino.HashDiff <> origen.HashDiff THEN
        UPDATE SET
            DeviceId               = origen.DeviceId,
            Time                    = origen.Time,
            InstalledCapacity       = origen.InstalledCapacity,
            PerpowerRatio           = origen.PerpowerRatio,
            ProductPower            = origen.ProductPower,
            KpiDataRaw              = origen.KpiDataRaw,
            CreationTime            = origen.CreationTime,
            LastModificationTime    = origen.LastModificationTime,
            IsDeleted               = origen.IsDeleted,
            HashDiff                = origen.HashDiff,
            FechaCargaInt           = SYSDATETIME(),
            RunId                   = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (
            Id, DeviceId, Time, InstalledCapacity, PerpowerRatio, ProductPower, KpiDataRaw,
            CreationTime, LastModificationTime, IsDeleted, HashDiff, RunId
        )
        VALUES (
            origen.Id, origen.DeviceId, origen.Time, origen.InstalledCapacity, origen.PerpowerRatio,
            origen.ProductPower, origen.KpiDataRaw, origen.CreationTime, origen.LastModificationTime,
            origen.IsDeleted, origen.HashDiff, @RunId
        )
    OUTPUT $action INTO #AccionesMerge;

    SELECT @NuevoWatermark = CONVERT(DATETIME2(3), MAX(v.Marca))
    FROM (
        SELECT CreationTime AS Marca FROM #Origen
        UNION ALL
        SELECT LastModificationTime FROM #Origen WHERE LastModificationTime IS NOT NULL
    ) v;
    SET @NuevoWatermark = ISNULL(@NuevoWatermark, @Desde);

    SELECT
        @FilasLeidas                                                                 AS FilasLeidas,
        ISNULL(SUM(CASE WHEN Accion = 'INSERT' THEN 1 ELSE 0 END), 0)                AS FilasInsertadas,
        ISNULL(SUM(CASE WHEN Accion = 'UPDATE' THEN 1 ELSE 0 END), 0)                AS FilasActualizadas,
        @FilasLeidas - ISNULL(SUM(CASE WHEN Accion = 'INSERT' THEN 1 ELSE 0 END), 0)
                      - ISNULL(SUM(CASE WHEN Accion = 'UPDATE' THEN 1 ELSE 0 END), 0) AS FilasIgnoradas,
        @NuevoWatermark                                                              AS NuevoWatermark
    FROM #AccionesMerge;

    DROP TABLE #Origen;
END
GO

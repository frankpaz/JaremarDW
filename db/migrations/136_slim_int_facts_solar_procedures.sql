-- 136: SPs de merge Bronze -> Silver de los hechos Solar, recortados a las
-- columnas que consumen las vistas de analisis (ver 135). Misma logica de
-- carga incremental por watermark (truncado a milisegundo) y de dedup por Id
-- que las versiones anteriores; solo cambia la lista de columnas.

CREATE OR ALTER PROCEDURE [int].usp_MergeFactSmaPower15Minutes
    @RunId            INT,
    @UltimoWatermark  DATETIME2(7) = NULL,
    @NuevoWatermark   DATETIME2(7) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Desde DATETIME2(3) = CONVERT(DATETIME2(3), ISNULL(@UltimoWatermark, '1900-01-01'));

    ;WITH StgIncremental AS (
        SELECT s.*
        FROM stg.factSmaPower15Minutes s
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
            RTRIM(s.DeviceId)                    AS DeviceId,
            RTRIM(s.Resolution)                  AS Resolution,
            s.Time,
            s.PvGeneration,
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

    MERGE [int].factSmaPower15Minutes AS destino
        USING #Origen AS origen
        ON destino.Id = origen.Id
    WHEN MATCHED AND destino.HashDiff <> origen.HashDiff THEN
        UPDATE SET
            DeviceId                = origen.DeviceId,
            Resolution              = origen.Resolution,
            Time                    = origen.Time,
            PvGeneration            = origen.PvGeneration,
            CreationTime            = origen.CreationTime,
            LastModificationTime    = origen.LastModificationTime,
            IsDeleted               = origen.IsDeleted,
            HashDiff                = origen.HashDiff,
            FechaCargaInt           = SYSDATETIME(),
            RunId                   = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (Id, DeviceId, Resolution, Time, PvGeneration, CreationTime, LastModificationTime, IsDeleted, HashDiff, RunId)
        VALUES (origen.Id, origen.DeviceId, origen.Resolution, origen.Time, origen.PvGeneration,
                origen.CreationTime, origen.LastModificationTime, origen.IsDeleted, origen.HashDiff, @RunId)
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
            TRY_CONVERT(DECIMAL(18,3), JSON_VALUE(s.KpiData, '$.product_power'))      AS ProductPower,
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
            ProductPower            = origen.ProductPower,
            CreationTime            = origen.CreationTime,
            LastModificationTime    = origen.LastModificationTime,
            IsDeleted               = origen.IsDeleted,
            HashDiff                = origen.HashDiff,
            FechaCargaInt           = SYSDATETIME(),
            RunId                   = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (Id, DeviceId, Time, ProductPower, CreationTime, LastModificationTime, IsDeleted, HashDiff, RunId)
        VALUES (origen.Id, origen.DeviceId, origen.Time, origen.ProductPower,
                origen.CreationTime, origen.LastModificationTime, origen.IsDeleted, origen.HashDiff, @RunId)
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

CREATE OR ALTER PROCEDURE [int].usp_MergeFactSoliscloudEnergyAndPowerPv
    @RunId            INT,
    @UltimoWatermark  DATETIME2(7) = NULL,
    @NuevoWatermark   DATETIME2(7) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Desde DATETIME2(3) = CONVERT(DATETIME2(3), ISNULL(@UltimoWatermark, '1900-01-01'));

    ;WITH StgIncremental AS (
        SELECT s.*
        FROM stg.factSoliscloudEnergyAndPowerPv s
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
            RTRIM(s.DeviceId)                                            AS DeviceId,
            DATEADD(SECOND, s.Time / 1000, '1970-01-01')                 AS Time,
            TRY_CONVERT(DECIMAL(18,4), JSON_VALUE(s.KpiData, '$.eToday')) AS EToday,
            TRY_CONVERT(DECIMAL(18,4), JSON_VALUE(s.KpiData, '$.gridSellTodayEnergy')) AS GridSellTodayEnergy,
            TRY_CONVERT(DECIMAL(18,4), JSON_VALUE(s.KpiData, '$.gridPurchasedTodayEnergy')) AS GridPurchasedTodayEnergy,
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

    MERGE [int].factSoliscloudEnergyAndPowerPv AS destino
        USING #Origen AS origen
        ON destino.Id = origen.Id
    WHEN MATCHED AND destino.HashDiff <> origen.HashDiff THEN
        UPDATE SET
            DeviceId                 = origen.DeviceId,
            Time                     = origen.Time,
            EToday                   = origen.EToday,
            GridSellTodayEnergy      = origen.GridSellTodayEnergy,
            GridPurchasedTodayEnergy = origen.GridPurchasedTodayEnergy,
            CreationTime             = origen.CreationTime,
            LastModificationTime     = origen.LastModificationTime,
            IsDeleted                = origen.IsDeleted,
            HashDiff                 = origen.HashDiff,
            FechaCargaInt            = SYSDATETIME(),
            RunId                    = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (Id, DeviceId, Time, EToday, GridSellTodayEnergy, GridPurchasedTodayEnergy,
                CreationTime, LastModificationTime, IsDeleted, HashDiff, RunId)
        VALUES (origen.Id, origen.DeviceId, origen.Time, origen.EToday, origen.GridSellTodayEnergy,
                origen.GridPurchasedTodayEnergy, origen.CreationTime, origen.LastModificationTime,
                origen.IsDeleted, origen.HashDiff, @RunId)
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

CREATE OR ALTER PROCEDURE [int].usp_MergeFactGrowattEnergyAndPowerPv
    @RunId            INT,
    @UltimoWatermark  DATETIME2(7) = NULL,
    @NuevoWatermark   DATETIME2(7) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Desde DATETIME2(3) = CONVERT(DATETIME2(3), ISNULL(@UltimoWatermark, '1900-01-01'));

    ;WITH StgIncremental AS (
        SELECT s.*
        FROM stg.factGrowattEnergyAndPowerPv s
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
            RTRIM(s.DeviceId)                    AS DeviceId,
            s.Time,
            s.EacToday,
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

    MERGE [int].factGrowattEnergyAndPowerPv AS destino
        USING #Origen AS origen
        ON destino.Id = origen.Id
    WHEN MATCHED AND destino.HashDiff <> origen.HashDiff THEN
        UPDATE SET
            DeviceId                = origen.DeviceId,
            Time                     = origen.Time,
            EacToday                 = origen.EacToday,
            CreationTime             = origen.CreationTime,
            LastModificationTime     = origen.LastModificationTime,
            IsDeleted                = origen.IsDeleted,
            HashDiff                 = origen.HashDiff,
            FechaCargaInt            = SYSDATETIME(),
            RunId                    = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (Id, DeviceId, Time, EacToday, CreationTime, LastModificationTime, IsDeleted, HashDiff, RunId)
        VALUES (origen.Id, origen.DeviceId, origen.Time, origen.EacToday, origen.CreationTime,
                origen.LastModificationTime, origen.IsDeleted, origen.HashDiff, @RunId)
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

CREATE OR ALTER PROCEDURE [int].usp_MergeFactMeteoDaily
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.factMeteoDaily);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH StgDeduplicado AS (
        SELECT s.*,
               ROW_NUMBER() OVER (PARTITION BY RTRIM(s.Site), s.MeasuredDate ORDER BY s.LoadedAt DESC) AS rn
        FROM stg.factMeteoDaily s
        WHERE RTRIM(ISNULL(s.Site, '')) <> '' AND s.MeasuredDate IS NOT NULL
    ),
    StgNormalizado AS (
        SELECT
            RTRIM(s.Site)                    AS Site,
            s.MeasuredDate,
            s.GhiRealWhM2,
            s.HsfRealHrs,
            s.WindSpeedRealMps,
            RTRIM(s.Source)                  AS Source,
            s.RetrievedAt
        FROM StgDeduplicado s
        WHERE s.rn = 1
    ),
    StgConHash AS (
        SELECT
            n.*,
            HASHBYTES('SHA2_256', (SELECT n.* FOR XML RAW, BINARY BASE64)) AS HashDiff
        FROM StgNormalizado n
    )
    MERGE [int].factMeteoDaily AS destino
        USING StgConHash AS origen
        ON destino.Site = origen.Site AND destino.MeasuredDate = origen.MeasuredDate
    WHEN MATCHED AND destino.HashDiff <> origen.HashDiff THEN
        UPDATE SET
            GhiRealWhM2      = origen.GhiRealWhM2,
            HsfRealHrs       = origen.HsfRealHrs,
            WindSpeedRealMps = origen.WindSpeedRealMps,
            Source           = origen.Source,
            RetrievedAt      = origen.RetrievedAt,
            EsVigente        = 1,
            HashDiff         = origen.HashDiff,
            FechaCargaInt    = SYSDATETIME(),
            RunId            = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (Site, MeasuredDate, GhiRealWhM2, HsfRealHrs, WindSpeedRealMps, Source, RetrievedAt, HashDiff, RunId)
        VALUES (origen.Site, origen.MeasuredDate, origen.GhiRealWhM2, origen.HsfRealHrs, origen.WindSpeedRealMps,
                origen.Source, origen.RetrievedAt, origen.HashDiff, @RunId)
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

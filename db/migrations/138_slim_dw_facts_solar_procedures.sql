-- 138: SPs de merge Silver -> Gold de los hechos Solar, recortados a las
-- columnas que consumen las vistas de analisis (ver 137). Misma logica que
-- las versiones anteriores (incremental por FechaCargaInt, resolucion de
-- llave de dispositivo por LEFT JOIN); solo cambia la lista de columnas.
-- Soliscloud conserva el JOIN por DeviceSn y la condicion de MATCHED que
-- rellena SoliscloudDeviceKey NULL (fix de la 091).

CREATE OR ALTER PROCEDURE dw.usp_MergeFactSmaPower15Minutes
    @RunId            INT,
    @UltimoWatermark  DATETIME2(7) = NULL,
    @NuevoWatermark   DATETIME2(7) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Desde DATETIME2(3) = CONVERT(DATETIME2(3), ISNULL(@UltimoWatermark, '1900-01-01'));

    ;WITH Origen AS (
        SELECT
            f.Id,
            d.SmaDeviceKey,
            f.DeviceId,
            f.Resolution,
            f.Time,
            f.PvGeneration,
            f.CreationTime,
            f.LastModificationTime,
            f.IsDeleted,
            f.HashDiff,
            f.FechaCargaInt
        FROM [int].factSmaPower15Minutes f
        LEFT JOIN dw.dimSmaDevices d ON d.DeviceId = TRY_CONVERT(BIGINT, f.DeviceId)
        WHERE CONVERT(DATETIME2(3), f.FechaCargaInt) > @Desde AND f.IsDeleted = 0
    )
    SELECT * INTO #Origen FROM Origen;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM #Origen);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    MERGE dw.factSmaPower15Minutes AS destino
        USING #Origen AS origen
        ON destino.Id = origen.Id
    WHEN MATCHED AND destino.HashDiff <> origen.HashDiff THEN
        UPDATE SET
            SmaDeviceKey          = origen.SmaDeviceKey,
            DeviceId              = origen.DeviceId,
            Resolution            = origen.Resolution,
            Time                  = origen.Time,
            PvGeneration          = origen.PvGeneration,
            CreationTime          = origen.CreationTime,
            LastModificationTime  = origen.LastModificationTime,
            IsDeleted             = origen.IsDeleted,
            HashDiff              = origen.HashDiff,
            FechaCargaDw          = SYSDATETIME(),
            RunId                 = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (Id, SmaDeviceKey, DeviceId, Resolution, Time, PvGeneration, CreationTime,
                LastModificationTime, IsDeleted, HashDiff, RunId)
        VALUES (origen.Id, origen.SmaDeviceKey, origen.DeviceId, origen.Resolution, origen.Time,
                origen.PvGeneration, origen.CreationTime, origen.LastModificationTime,
                origen.IsDeleted, origen.HashDiff, @RunId)
    OUTPUT $action INTO #AccionesMerge;

    SELECT @NuevoWatermark = CONVERT(DATETIME2(3), MAX(FechaCargaInt)) FROM #Origen;
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

CREATE OR ALTER PROCEDURE dw.usp_MergeFactHuaweiEnergyAndPowerPv
    @RunId            INT,
    @UltimoWatermark  DATETIME2(7) = NULL,
    @NuevoWatermark   DATETIME2(7) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Desde DATETIME2(3) = CONVERT(DATETIME2(3), ISNULL(@UltimoWatermark, '1900-01-01'));

    ;WITH Origen AS (
        SELECT
            f.Id,
            d.HuaweiDeviceKey,
            f.DeviceId,
            f.Time,
            f.ProductPower,
            f.CreationTime,
            f.LastModificationTime,
            f.IsDeleted,
            f.HashDiff,
            f.FechaCargaInt
        FROM [int].factHuaweiEnergyAndPowerPv f
        LEFT JOIN dw.dimHuaweiDevices d ON d.DeviceId = f.DeviceId
        WHERE CONVERT(DATETIME2(3), f.FechaCargaInt) > @Desde AND f.IsDeleted = 0
    )
    SELECT * INTO #Origen FROM Origen;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM #Origen);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    MERGE dw.factHuaweiEnergyAndPowerPv AS destino
        USING #Origen AS origen
        ON destino.Id = origen.Id
    WHEN MATCHED AND destino.HashDiff <> origen.HashDiff THEN
        UPDATE SET
            HuaweiDeviceKey       = origen.HuaweiDeviceKey,
            DeviceId              = origen.DeviceId,
            Time                  = origen.Time,
            ProductPower          = origen.ProductPower,
            CreationTime          = origen.CreationTime,
            LastModificationTime  = origen.LastModificationTime,
            IsDeleted             = origen.IsDeleted,
            HashDiff              = origen.HashDiff,
            FechaCargaDw          = SYSDATETIME(),
            RunId                 = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (Id, HuaweiDeviceKey, DeviceId, Time, ProductPower, CreationTime,
                LastModificationTime, IsDeleted, HashDiff, RunId)
        VALUES (origen.Id, origen.HuaweiDeviceKey, origen.DeviceId, origen.Time, origen.ProductPower,
                origen.CreationTime, origen.LastModificationTime, origen.IsDeleted, origen.HashDiff, @RunId)
    OUTPUT $action INTO #AccionesMerge;

    SELECT @NuevoWatermark = CONVERT(DATETIME2(3), MAX(FechaCargaInt)) FROM #Origen;
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

CREATE OR ALTER PROCEDURE dw.usp_MergeFactSoliscloudEnergyAndPowerPv
    @RunId            INT,
    @UltimoWatermark  DATETIME2(7) = NULL,
    @NuevoWatermark   DATETIME2(7) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Desde DATETIME2(3) = CONVERT(DATETIME2(3), ISNULL(@UltimoWatermark, '1900-01-01'));

    ;WITH Origen AS (
        SELECT
            f.Id,
            d.SoliscloudDeviceKey,
            f.DeviceId,
            f.Time,
            f.EToday,
            f.GridSellTodayEnergy,
            f.GridPurchasedTodayEnergy,
            f.CreationTime,
            f.LastModificationTime,
            f.IsDeleted,
            f.HashDiff,
            f.FechaCargaInt
        FROM [int].factSoliscloudEnergyAndPowerPv f
        LEFT JOIN dw.dimSoliscloudDevices d ON d.DeviceSn = f.DeviceId
        WHERE CONVERT(DATETIME2(3), f.FechaCargaInt) > @Desde AND f.IsDeleted = 0
    )
    SELECT * INTO #Origen FROM Origen;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM #Origen);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    MERGE dw.factSoliscloudEnergyAndPowerPv AS destino
        USING #Origen AS origen
        ON destino.Id = origen.Id
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR (destino.SoliscloudDeviceKey IS NULL AND origen.SoliscloudDeviceKey IS NOT NULL)) THEN
        UPDATE SET
            SoliscloudDeviceKey      = origen.SoliscloudDeviceKey,
            DeviceId                 = origen.DeviceId,
            Time                     = origen.Time,
            EToday                   = origen.EToday,
            GridSellTodayEnergy      = origen.GridSellTodayEnergy,
            GridPurchasedTodayEnergy = origen.GridPurchasedTodayEnergy,
            CreationTime             = origen.CreationTime,
            LastModificationTime     = origen.LastModificationTime,
            IsDeleted                = origen.IsDeleted,
            HashDiff                 = origen.HashDiff,
            FechaCargaDw             = SYSDATETIME(),
            RunId                    = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (Id, SoliscloudDeviceKey, DeviceId, Time, EToday, GridSellTodayEnergy, GridPurchasedTodayEnergy,
                CreationTime, LastModificationTime, IsDeleted, HashDiff, RunId)
        VALUES (origen.Id, origen.SoliscloudDeviceKey, origen.DeviceId, origen.Time, origen.EToday,
                origen.GridSellTodayEnergy, origen.GridPurchasedTodayEnergy, origen.CreationTime,
                origen.LastModificationTime, origen.IsDeleted, origen.HashDiff, @RunId)
    OUTPUT $action INTO #AccionesMerge;

    SELECT @NuevoWatermark = CONVERT(DATETIME2(3), MAX(FechaCargaInt)) FROM #Origen;
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

CREATE OR ALTER PROCEDURE dw.usp_MergeFactGrowattEnergyAndPowerPv
    @RunId            INT,
    @UltimoWatermark  DATETIME2(7) = NULL,
    @NuevoWatermark   DATETIME2(7) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Desde DATETIME2(3) = CONVERT(DATETIME2(3), ISNULL(@UltimoWatermark, '1900-01-01'));

    ;WITH Origen AS (
        SELECT
            f.Id,
            f.DeviceId,
            f.Time,
            f.EacToday,
            f.CreationTime,
            f.LastModificationTime,
            f.IsDeleted,
            f.HashDiff,
            f.FechaCargaInt
        FROM [int].factGrowattEnergyAndPowerPv f
        WHERE CONVERT(DATETIME2(3), f.FechaCargaInt) > @Desde AND f.IsDeleted = 0
    )
    SELECT * INTO #Origen FROM Origen;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM #Origen);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    MERGE dw.factGrowattEnergyAndPowerPv AS destino
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
            FechaCargaDw             = SYSDATETIME(),
            RunId                    = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (Id, DeviceId, Time, EacToday, CreationTime, LastModificationTime, IsDeleted, HashDiff, RunId)
        VALUES (origen.Id, origen.DeviceId, origen.Time, origen.EacToday, origen.CreationTime,
                origen.LastModificationTime, origen.IsDeleted, origen.HashDiff, @RunId)
    OUTPUT $action INTO #AccionesMerge;

    SELECT @NuevoWatermark = CONVERT(DATETIME2(3), MAX(FechaCargaInt)) FROM #Origen;
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

CREATE OR ALTER PROCEDURE dw.usp_MergeFactMeteoDaily
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].factMeteoDaily);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH Origen AS (
        SELECT
            Site, MeasuredDate, GhiRealWhM2, HsfRealHrs, WindSpeedRealMps, Source,
            RetrievedAt, EsVigente, HashDiff
        FROM [int].factMeteoDaily
    )
    MERGE dw.factMeteoDaily AS destino
        USING Origen AS origen
        ON destino.Site = origen.Site AND destino.MeasuredDate = origen.MeasuredDate
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente) THEN
        UPDATE SET
            GhiRealWhM2      = origen.GhiRealWhM2,
            HsfRealHrs       = origen.HsfRealHrs,
            WindSpeedRealMps = origen.WindSpeedRealMps,
            Source           = origen.Source,
            RetrievedAt      = origen.RetrievedAt,
            EsVigente        = origen.EsVigente,
            HashDiff         = origen.HashDiff,
            FechaCargaDw     = SYSDATETIME(),
            RunId            = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (Site, MeasuredDate, GhiRealWhM2, HsfRealHrs, WindSpeedRealMps, Source, RetrievedAt, EsVigente, HashDiff, RunId)
        VALUES (origen.Site, origen.MeasuredDate, origen.GhiRealWhM2, origen.HsfRealHrs, origen.WindSpeedRealMps,
                origen.Source, origen.RetrievedAt, origen.EsVigente, origen.HashDiff, @RunId)
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

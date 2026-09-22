-- 086: merge Silver -> Gold para factHuaweiEnergyAndPowerPv. INCREMENTAL,
-- mismo patron de watermark que los facts SMA.

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
            f.InstalledCapacity,
            f.PerpowerRatio,
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
            InstalledCapacity     = origen.InstalledCapacity,
            PerpowerRatio         = origen.PerpowerRatio,
            ProductPower          = origen.ProductPower,
            CreationTime          = origen.CreationTime,
            LastModificationTime  = origen.LastModificationTime,
            IsDeleted             = origen.IsDeleted,
            HashDiff              = origen.HashDiff,
            FechaCargaDw          = SYSDATETIME(),
            RunId                 = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (
            Id, HuaweiDeviceKey, DeviceId, Time, InstalledCapacity, PerpowerRatio, ProductPower,
            CreationTime, LastModificationTime, IsDeleted, HashDiff, RunId
        )
        VALUES (
            origen.Id, origen.HuaweiDeviceKey, origen.DeviceId, origen.Time, origen.InstalledCapacity,
            origen.PerpowerRatio, origen.ProductPower, origen.CreationTime, origen.LastModificationTime,
            origen.IsDeleted, origen.HashDiff, @RunId
        )
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

-- 082: merge Silver -> Gold para factSmaPower15Minutes. INCREMENTAL, mismo
-- patron que factSmaPowerPlanta (con el fix de precision de watermark
-- incluido desde el inicio).

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
            p.SmaPlantaKey,
            d.SmaDeviceKey,
            f.PlantId,
            f.DeviceId,
            f.SetType,
            f.Resolution,
            f.UnidadDeMedida,
            f.Time,
            f.PvGeneration,
            f.CreationTime,
            f.LastModificationTime,
            f.IsDeleted,
            f.HashDiff,
            f.FechaCargaInt
        FROM [int].factSmaPower15Minutes f
        LEFT JOIN dw.dimSmaPlants p ON p.PlantId = TRY_CONVERT(INT, f.PlantId)
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
            SmaPlantaKey          = origen.SmaPlantaKey,
            SmaDeviceKey          = origen.SmaDeviceKey,
            PlantId               = origen.PlantId,
            DeviceId              = origen.DeviceId,
            SetType               = origen.SetType,
            Resolution            = origen.Resolution,
            UnidadDeMedida        = origen.UnidadDeMedida,
            Time                  = origen.Time,
            PvGeneration          = origen.PvGeneration,
            CreationTime          = origen.CreationTime,
            LastModificationTime  = origen.LastModificationTime,
            IsDeleted             = origen.IsDeleted,
            HashDiff              = origen.HashDiff,
            FechaCargaDw          = SYSDATETIME(),
            RunId                 = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (
            Id, SmaPlantaKey, SmaDeviceKey, PlantId, DeviceId, SetType, Resolution, UnidadDeMedida,
            Time, PvGeneration, CreationTime, LastModificationTime, IsDeleted, HashDiff, RunId
        )
        VALUES (
            origen.Id, origen.SmaPlantaKey, origen.SmaDeviceKey, origen.PlantId, origen.DeviceId, origen.SetType,
            origen.Resolution, origen.UnidadDeMedida, origen.Time, origen.PvGeneration, origen.CreationTime,
            origen.LastModificationTime, origen.IsDeleted, origen.HashDiff, @RunId
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

-- 078: corrige perdida de precision en el watermark incremental de
-- factSmaPowerPlanta. FechaCargaInt/CreationTime son DATETIME2(7) (100ns),
-- pero el watermark viaja por Python (pyodbc datetime = microsegundos, 6
-- digitos) entre corridas -- el ultimo digito se trunca en el viaje de ida
-- y vuelta, y la fila limite del watermark anterior vuelve a calificar en
-- el filtro "> @Desde" en cada corrida (no duplica datos, el MERGE la
-- ignora por HashDiff igual, pero rehace el escaneo de esa fila
-- indefinidamente). Se trunca la comparacion y el nuevo watermark a
-- milisegundo (DATETIME2(3)), precision que Python preserva exacta.

CREATE OR ALTER PROCEDURE [int].usp_MergeFactSmaPowerPlanta
    @RunId            INT,
    @UltimoWatermark  DATETIME2(7) = NULL,
    @NuevoWatermark   DATETIME2(7) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Desde DATETIME2(3) = CONVERT(DATETIME2(3), ISNULL(@UltimoWatermark, '1900-01-01'));

    ;WITH StgIncremental AS (
        SELECT s.*
        FROM stg.factSmaPowerPlanta s
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
            s.PlantId,
            RTRIM(s.DeviceId)                    AS DeviceId,
            s.SetType,
            RTRIM(s.Resolution)                  AS Resolution,
            RTRIM(s.UnidadDeMedida)               AS UnidadDeMedida,
            s.Time,
            s.PvGeneration,
            s.CreatorUserId,
            s.CreationTime,
            s.LastModifierUserId,
            s.LastModificationTime,
            s.DeleterUserId,
            s.DeletionTime,
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

    MERGE [int].factSmaPowerPlanta AS destino
        USING #Origen AS origen
        ON destino.Id = origen.Id
    WHEN MATCHED AND destino.HashDiff <> origen.HashDiff THEN
        UPDATE SET
            PlantId                = origen.PlantId,
            DeviceId                = origen.DeviceId,
            SetType                 = origen.SetType,
            Resolution              = origen.Resolution,
            UnidadDeMedida          = origen.UnidadDeMedida,
            Time                    = origen.Time,
            PvGeneration            = origen.PvGeneration,
            CreatorUserId           = origen.CreatorUserId,
            CreationTime            = origen.CreationTime,
            LastModifierUserId      = origen.LastModifierUserId,
            LastModificationTime    = origen.LastModificationTime,
            DeleterUserId           = origen.DeleterUserId,
            DeletionTime            = origen.DeletionTime,
            IsDeleted               = origen.IsDeleted,
            HashDiff                = origen.HashDiff,
            FechaCargaInt           = SYSDATETIME(),
            RunId                   = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (
            Id, PlantId, DeviceId, SetType, Resolution, UnidadDeMedida, Time, PvGeneration,
            CreatorUserId, CreationTime, LastModifierUserId, LastModificationTime,
            DeleterUserId, DeletionTime, IsDeleted, HashDiff, RunId
        )
        VALUES (
            origen.Id, origen.PlantId, origen.DeviceId, origen.SetType, origen.Resolution, origen.UnidadDeMedida,
            origen.Time, origen.PvGeneration, origen.CreatorUserId, origen.CreationTime, origen.LastModifierUserId,
            origen.LastModificationTime, origen.DeleterUserId, origen.DeletionTime, origen.IsDeleted,
            origen.HashDiff, @RunId
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

CREATE OR ALTER PROCEDURE dw.usp_MergeFactSmaPowerPlanta
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
        FROM [int].factSmaPowerPlanta f
        LEFT JOIN dw.dimSmaPlants p ON p.PlantId = TRY_CONVERT(INT, f.PlantId)
        LEFT JOIN dw.dimSmaDevices d ON d.DeviceId = TRY_CONVERT(BIGINT, f.DeviceId)
        WHERE CONVERT(DATETIME2(3), f.FechaCargaInt) > @Desde AND f.IsDeleted = 0
    )
    SELECT * INTO #Origen FROM Origen;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM #Origen);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    MERGE dw.factSmaPowerPlanta AS destino
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

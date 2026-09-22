-- 080: merge Bronze -> Silver para factSmaPower15Minutes. INCREMENTAL,
-- mismo patron que factSmaPowerPlanta (con el fix de precision de
-- watermark ya incluido desde el inicio: comparacion y @NuevoWatermark
-- truncados a milisegundo con CONVERT(DATETIME2(3), ...), porque
-- pyodbc/datetime solo preserva microsegundos y una comparacion en
-- DATETIME2(7) "cruda" reescanea la fila limite del watermark en cada
-- corrida).

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

    MERGE [int].factSmaPower15Minutes AS destino
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

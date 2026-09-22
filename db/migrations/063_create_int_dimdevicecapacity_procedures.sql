-- 063: merge Bronze -> Silver para dimDeviceCapacity.

CREATE OR ALTER PROCEDURE [int].usp_MergeDimDeviceCapacity
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.dimDeviceCapacity);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH StgDeduplicado AS (
        SELECT s.*,
               ROW_NUMBER() OVER (PARTITION BY RTRIM(s.InverterId) ORDER BY s.LoadedAt DESC) AS rn
        FROM stg.dimDeviceCapacity s
        WHERE RTRIM(ISNULL(s.InverterId, '')) <> ''
    ),
    StgNormalizado AS (
        SELECT
            RTRIM(s.InverterId)                    AS InverterId,
            RTRIM(s.Vendor)                         AS Vendor,
            RTRIM(s.PlantLabel)                     AS PlantLabel,
            RTRIM(s.ModelName)                      AS ModelName,
            RTRIM(s.JoinKeyKind)                    AS JoinKeyKind,
            NULLIF(RTRIM(s.JoinKey), '')            AS JoinKey,
            NULLIF(RTRIM(s.SourceSn), '')           AS SourceSn,
            s.CapacityDcKwp,
            s.CapacityAcKw,
            s.IsPlaceholder,
            NULLIF(RTRIM(s.SourceNote), '')         AS SourceNote,
            NULLIF(RTRIM(s.Source), '')             AS Source,
            TRY_CONVERT(DATE, s.ExtractedAt)        AS ExtractedAt,
            NULLIF(RTRIM(s.ExtractedBy), '')        AS ExtractedBy,
            s.LoadedAt                              AS SourceLoadedAt
        FROM StgDeduplicado s
        WHERE s.rn = 1
    ),
    StgConHash AS (
        SELECT
            n.*,
            HASHBYTES('SHA2_256', (SELECT n.* FOR XML RAW, BINARY BASE64)) AS HashDiff
        FROM StgNormalizado n
    )
    MERGE [int].dimDeviceCapacity AS destino
        USING StgConHash AS origen
        ON destino.InverterId = origen.InverterId
    WHEN MATCHED AND destino.HashDiff <> origen.HashDiff THEN
        UPDATE SET
            Vendor          = origen.Vendor,
            PlantLabel      = origen.PlantLabel,
            ModelName       = origen.ModelName,
            JoinKeyKind     = origen.JoinKeyKind,
            JoinKey         = origen.JoinKey,
            SourceSn        = origen.SourceSn,
            CapacityDcKwp   = origen.CapacityDcKwp,
            CapacityAcKw    = origen.CapacityAcKw,
            IsPlaceholder   = origen.IsPlaceholder,
            SourceNote      = origen.SourceNote,
            Source          = origen.Source,
            ExtractedAt     = origen.ExtractedAt,
            ExtractedBy     = origen.ExtractedBy,
            SourceLoadedAt  = origen.SourceLoadedAt,
            EsVigente       = 1,
            HashDiff        = origen.HashDiff,
            FechaCargaInt   = SYSDATETIME(),
            RunId           = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (
            InverterId, Vendor, PlantLabel, ModelName, JoinKeyKind, JoinKey, SourceSn,
            CapacityDcKwp, CapacityAcKw, IsPlaceholder, SourceNote, Source, ExtractedAt,
            ExtractedBy, SourceLoadedAt, HashDiff, RunId
        )
        VALUES (
            origen.InverterId, origen.Vendor, origen.PlantLabel, origen.ModelName, origen.JoinKeyKind,
            origen.JoinKey, origen.SourceSn, origen.CapacityDcKwp, origen.CapacityAcKw, origen.IsPlaceholder,
            origen.SourceNote, origen.Source, origen.ExtractedAt, origen.ExtractedBy, origen.SourceLoadedAt,
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

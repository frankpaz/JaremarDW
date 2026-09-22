-- 065: merge Silver -> Gold para dimDeviceCapacity. SCD Tipo 1 (sobrescribe).
-- Reutiliza el HashDiff ya calculado en [int].dimDeviceCapacity.

CREATE OR ALTER PROCEDURE dw.usp_MergeDimDeviceCapacity
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].dimDeviceCapacity);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH Origen AS (
        SELECT
            InverterId, Vendor, PlantLabel, ModelName, JoinKeyKind, JoinKey, SourceSn,
            CapacityDcKwp, CapacityAcKw, IsPlaceholder, SourceNote, Source, ExtractedAt,
            ExtractedBy, SourceLoadedAt, EsVigente, HashDiff
        FROM [int].dimDeviceCapacity
    )
    MERGE dw.dimDeviceCapacity AS destino
        USING Origen AS origen
        ON destino.InverterId = origen.InverterId
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente) THEN
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
            EsVigente       = origen.EsVigente,
            HashDiff        = origen.HashDiff,
            FechaCargaDw    = SYSDATETIME(),
            RunId           = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (
            InverterId, Vendor, PlantLabel, ModelName, JoinKeyKind, JoinKey, SourceSn,
            CapacityDcKwp, CapacityAcKw, IsPlaceholder, SourceNote, Source, ExtractedAt,
            ExtractedBy, SourceLoadedAt, EsVigente, HashDiff, RunId
        )
        VALUES (
            origen.InverterId, origen.Vendor, origen.PlantLabel, origen.ModelName, origen.JoinKeyKind,
            origen.JoinKey, origen.SourceSn, origen.CapacityDcKwp, origen.CapacityAcKw, origen.IsPlaceholder,
            origen.SourceNote, origen.Source, origen.ExtractedAt, origen.ExtractedBy, origen.SourceLoadedAt,
            origen.EsVigente, origen.HashDiff, @RunId
        )
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

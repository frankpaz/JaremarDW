-- 073: merge Silver -> Gold para dimGhiPlanDaily. SCD Tipo 1 (sobrescribe).
-- Reutiliza el HashDiff ya calculado en [int].dimGhiPlanDaily.

CREATE OR ALTER PROCEDURE dw.usp_MergeDimGhiPlanDaily
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].dimGhiPlanDaily);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH Origen AS (
        SELECT
            Site, DayOfYear, MonthOfYear, DayOfMonth, GhiP50WhM2, GhiP90WhM2, GhiP10WhM2,
            HsfP50Hrs, WindSpeedP50Mps, SampleCount, GsaVintage, SourceLoadedAt, EsVigente, HashDiff
        FROM [int].dimGhiPlanDaily
    )
    MERGE dw.dimGhiPlanDaily AS destino
        USING Origen AS origen
        ON destino.Site = origen.Site AND destino.DayOfYear = origen.DayOfYear
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente) THEN
        UPDATE SET
            MonthOfYear      = origen.MonthOfYear,
            DayOfMonth       = origen.DayOfMonth,
            GhiP50WhM2       = origen.GhiP50WhM2,
            GhiP90WhM2       = origen.GhiP90WhM2,
            GhiP10WhM2       = origen.GhiP10WhM2,
            HsfP50Hrs        = origen.HsfP50Hrs,
            WindSpeedP50Mps  = origen.WindSpeedP50Mps,
            SampleCount      = origen.SampleCount,
            GsaVintage       = origen.GsaVintage,
            SourceLoadedAt   = origen.SourceLoadedAt,
            EsVigente        = origen.EsVigente,
            HashDiff         = origen.HashDiff,
            FechaCargaDw     = SYSDATETIME(),
            RunId            = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (
            Site, DayOfYear, MonthOfYear, DayOfMonth, GhiP50WhM2, GhiP90WhM2, GhiP10WhM2,
            HsfP50Hrs, WindSpeedP50Mps, SampleCount, GsaVintage, SourceLoadedAt, EsVigente, HashDiff, RunId
        )
        VALUES (
            origen.Site, origen.DayOfYear, origen.MonthOfYear, origen.DayOfMonth, origen.GhiP50WhM2,
            origen.GhiP90WhM2, origen.GhiP10WhM2, origen.HsfP50Hrs, origen.WindSpeedP50Mps,
            origen.SampleCount, origen.GsaVintage, origen.SourceLoadedAt, origen.EsVigente, origen.HashDiff, @RunId
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

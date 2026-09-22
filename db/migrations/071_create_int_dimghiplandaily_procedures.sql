-- 071: merge Bronze -> Silver para dimGhiPlanDaily.

CREATE OR ALTER PROCEDURE [int].usp_MergeDimGhiPlanDaily
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.dimGhiPlanDaily);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH StgDeduplicado AS (
        SELECT s.*,
               ROW_NUMBER() OVER (PARTITION BY RTRIM(s.Site), s.DayOfYear ORDER BY s.LoadedAt DESC) AS rn
        FROM stg.dimGhiPlanDaily s
        WHERE RTRIM(ISNULL(s.Site, '')) <> '' AND s.DayOfYear IS NOT NULL
    ),
    StgNormalizado AS (
        SELECT
            RTRIM(s.Site)                    AS Site,
            s.DayOfYear,
            s.MonthOfYear,
            s.DayOfMonth,
            s.GhiP50WhM2,
            s.GhiP90WhM2,
            s.GhiP10WhM2,
            s.HsfP50Hrs,
            s.WindSpeedP50Mps,
            s.SampleCount,
            NULLIF(RTRIM(s.GsaVintage), '')  AS GsaVintage,
            s.LoadedAt                       AS SourceLoadedAt
        FROM StgDeduplicado s
        WHERE s.rn = 1
    ),
    StgConHash AS (
        SELECT
            n.*,
            HASHBYTES('SHA2_256', (SELECT n.* FOR XML RAW, BINARY BASE64)) AS HashDiff
        FROM StgNormalizado n
    )
    MERGE [int].dimGhiPlanDaily AS destino
        USING StgConHash AS origen
        ON destino.Site = origen.Site AND destino.DayOfYear = origen.DayOfYear
    WHEN MATCHED AND destino.HashDiff <> origen.HashDiff THEN
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
            EsVigente        = 1,
            HashDiff         = origen.HashDiff,
            FechaCargaInt    = SYSDATETIME(),
            RunId            = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (
            Site, DayOfYear, MonthOfYear, DayOfMonth, GhiP50WhM2, GhiP90WhM2, GhiP10WhM2,
            HsfP50Hrs, WindSpeedP50Mps, SampleCount, GsaVintage, SourceLoadedAt, HashDiff, RunId
        )
        VALUES (
            origen.Site, origen.DayOfYear, origen.MonthOfYear, origen.DayOfMonth, origen.GhiP50WhM2,
            origen.GhiP90WhM2, origen.GhiP10WhM2, origen.HsfP50Hrs, origen.WindSpeedP50Mps,
            origen.SampleCount, origen.GsaVintage, origen.SourceLoadedAt, origen.HashDiff, @RunId
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

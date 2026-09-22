-- 095: merge Silver -> Gold para factMeteoDaily. SCD Tipo 1 (sobrescribe).
-- Reutiliza el HashDiff ya calculado en [int].factMeteoDaily.

CREATE OR ALTER PROCEDURE dw.usp_MergeFactMeteoDaily
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].factMeteoDaily);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH Origen AS (
        SELECT
            Site, MeasuredDate, GhiRealWhM2, HsfRealHrs, WindSpeedRealMps, Source, SourceVersion,
            RetrievedAt, SourceLoadedAt, EsVigente, HashDiff
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
            SourceVersion    = origen.SourceVersion,
            RetrievedAt      = origen.RetrievedAt,
            SourceLoadedAt   = origen.SourceLoadedAt,
            EsVigente        = origen.EsVigente,
            HashDiff         = origen.HashDiff,
            FechaCargaDw     = SYSDATETIME(),
            RunId            = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (Site, MeasuredDate, GhiRealWhM2, HsfRealHrs, WindSpeedRealMps, Source, SourceVersion, RetrievedAt, SourceLoadedAt, EsVigente, HashDiff, RunId)
        VALUES (origen.Site, origen.MeasuredDate, origen.GhiRealWhM2, origen.HsfRealHrs, origen.WindSpeedRealMps,
                origen.Source, origen.SourceVersion, origen.RetrievedAt, origen.SourceLoadedAt, origen.EsVigente, origen.HashDiff, @RunId)
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

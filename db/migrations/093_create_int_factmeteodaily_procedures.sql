-- 093: merge Bronze -> Silver para factMeteoDaily. Carga FULL (mismo patron
-- que las dimensiones meteo), no incremental por watermark.

CREATE OR ALTER PROCEDURE [int].usp_MergeFactMeteoDaily
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.factMeteoDaily);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH StgDeduplicado AS (
        SELECT s.*,
               ROW_NUMBER() OVER (PARTITION BY RTRIM(s.Site), s.MeasuredDate ORDER BY s.LoadedAt DESC) AS rn
        FROM stg.factMeteoDaily s
        WHERE RTRIM(ISNULL(s.Site, '')) <> '' AND s.MeasuredDate IS NOT NULL
    ),
    StgNormalizado AS (
        SELECT
            RTRIM(s.Site)                    AS Site,
            s.MeasuredDate,
            s.GhiRealWhM2,
            s.HsfRealHrs,
            s.WindSpeedRealMps,
            RTRIM(s.Source)                  AS Source,
            NULLIF(RTRIM(s.SourceVersion), '') AS SourceVersion,
            s.RetrievedAt,
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
    MERGE [int].factMeteoDaily AS destino
        USING StgConHash AS origen
        ON destino.Site = origen.Site AND destino.MeasuredDate = origen.MeasuredDate
    WHEN MATCHED AND destino.HashDiff <> origen.HashDiff THEN
        UPDATE SET
            GhiRealWhM2      = origen.GhiRealWhM2,
            HsfRealHrs       = origen.HsfRealHrs,
            WindSpeedRealMps = origen.WindSpeedRealMps,
            Source           = origen.Source,
            SourceVersion    = origen.SourceVersion,
            RetrievedAt      = origen.RetrievedAt,
            SourceLoadedAt   = origen.SourceLoadedAt,
            EsVigente        = 1,
            HashDiff         = origen.HashDiff,
            FechaCargaInt    = SYSDATETIME(),
            RunId            = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (Site, MeasuredDate, GhiRealWhM2, HsfRealHrs, WindSpeedRealMps, Source, SourceVersion, RetrievedAt, SourceLoadedAt, HashDiff, RunId)
        VALUES (origen.Site, origen.MeasuredDate, origen.GhiRealWhM2, origen.HsfRealHrs, origen.WindSpeedRealMps,
                origen.Source, origen.SourceVersion, origen.RetrievedAt, origen.SourceLoadedAt, origen.HashDiff, @RunId)
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

-- 067: merge Bronze -> Silver para dimGsaMonthlyReference.

CREATE OR ALTER PROCEDURE [int].usp_MergeDimGsaMonthlyReference
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.dimGsaMonthlyReference);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH StgDeduplicado AS (
        SELECT s.*,
               ROW_NUMBER() OVER (PARTITION BY RTRIM(s.Site), s.MonthOfYear ORDER BY s.LoadedAt DESC) AS rn
        FROM stg.dimGsaMonthlyReference s
        WHERE RTRIM(ISNULL(s.Site, '')) <> '' AND s.MonthOfYear IS NOT NULL
    ),
    StgNormalizado AS (
        SELECT
            RTRIM(s.Site)                       AS Site,
            s.MonthOfYear,
            s.GhiKwhM2Day,
            s.DifKwhM2Day,
            s.DniKwhM2Day,
            NULLIF(RTRIM(s.SiteName), '')       AS SiteName,
            s.Lat,
            s.Lon,
            RTRIM(s.Units)                       AS Units,
            NULLIF(RTRIM(s.Source), '')         AS Source,
            NULLIF(RTRIM(s.Dataset), '')        AS Dataset,
            NULLIF(RTRIM(s.Segment), '')        AS Segment,
            NULLIF(RTRIM(s.Vintage), '')        AS Vintage,
            TRY_CONVERT(DATE, s.ExtractedAt)    AS ExtractedAt,
            NULLIF(RTRIM(s.ExtractedBy), '')    AS ExtractedBy,
            s.GhiAnnualWeb,
            s.LoadedAt                          AS SourceLoadedAt
        FROM StgDeduplicado s
        WHERE s.rn = 1
    ),
    StgConHash AS (
        SELECT
            n.*,
            HASHBYTES('SHA2_256', (SELECT n.* FOR XML RAW, BINARY BASE64)) AS HashDiff
        FROM StgNormalizado n
    )
    MERGE [int].dimGsaMonthlyReference AS destino
        USING StgConHash AS origen
        ON destino.Site = origen.Site AND destino.MonthOfYear = origen.MonthOfYear
    WHEN MATCHED AND destino.HashDiff <> origen.HashDiff THEN
        UPDATE SET
            GhiKwhM2Day     = origen.GhiKwhM2Day,
            DifKwhM2Day     = origen.DifKwhM2Day,
            DniKwhM2Day     = origen.DniKwhM2Day,
            SiteName        = origen.SiteName,
            Lat             = origen.Lat,
            Lon             = origen.Lon,
            Units           = origen.Units,
            Source          = origen.Source,
            Dataset         = origen.Dataset,
            Segment         = origen.Segment,
            Vintage         = origen.Vintage,
            ExtractedAt     = origen.ExtractedAt,
            ExtractedBy     = origen.ExtractedBy,
            GhiAnnualWeb    = origen.GhiAnnualWeb,
            SourceLoadedAt  = origen.SourceLoadedAt,
            EsVigente       = 1,
            HashDiff        = origen.HashDiff,
            FechaCargaInt   = SYSDATETIME(),
            RunId           = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (
            Site, MonthOfYear, GhiKwhM2Day, DifKwhM2Day, DniKwhM2Day, SiteName, Lat, Lon, Units,
            Source, Dataset, Segment, Vintage, ExtractedAt, ExtractedBy, GhiAnnualWeb, SourceLoadedAt, HashDiff, RunId
        )
        VALUES (
            origen.Site, origen.MonthOfYear, origen.GhiKwhM2Day, origen.DifKwhM2Day, origen.DniKwhM2Day,
            origen.SiteName, origen.Lat, origen.Lon, origen.Units, origen.Source, origen.Dataset, origen.Segment,
            origen.Vintage, origen.ExtractedAt, origen.ExtractedBy, origen.GhiAnnualWeb, origen.SourceLoadedAt,
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

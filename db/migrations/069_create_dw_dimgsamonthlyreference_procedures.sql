-- 069: merge Silver -> Gold para dimGsaMonthlyReference. SCD Tipo 1
-- (sobrescribe). Reutiliza el HashDiff ya calculado en
-- [int].dimGsaMonthlyReference.

CREATE OR ALTER PROCEDURE dw.usp_MergeDimGsaMonthlyReference
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].dimGsaMonthlyReference);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH Origen AS (
        SELECT
            Site, MonthOfYear, GhiKwhM2Day, DifKwhM2Day, DniKwhM2Day, SiteName, Lat, Lon, Units,
            Source, Dataset, Segment, Vintage, ExtractedAt, ExtractedBy, GhiAnnualWeb, SourceLoadedAt,
            EsVigente, HashDiff
        FROM [int].dimGsaMonthlyReference
    )
    MERGE dw.dimGsaMonthlyReference AS destino
        USING Origen AS origen
        ON destino.Site = origen.Site AND destino.MonthOfYear = origen.MonthOfYear
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente) THEN
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
            EsVigente       = origen.EsVigente,
            HashDiff        = origen.HashDiff,
            FechaCargaDw    = SYSDATETIME(),
            RunId           = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (
            Site, MonthOfYear, GhiKwhM2Day, DifKwhM2Day, DniKwhM2Day, SiteName, Lat, Lon, Units,
            Source, Dataset, Segment, Vintage, ExtractedAt, ExtractedBy, GhiAnnualWeb, SourceLoadedAt,
            EsVigente, HashDiff, RunId
        )
        VALUES (
            origen.Site, origen.MonthOfYear, origen.GhiKwhM2Day, origen.DifKwhM2Day, origen.DniKwhM2Day,
            origen.SiteName, origen.Lat, origen.Lon, origen.Units, origen.Source, origen.Dataset, origen.Segment,
            origen.Vintage, origen.ExtractedAt, origen.ExtractedBy, origen.GhiAnnualWeb, origen.SourceLoadedAt,
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

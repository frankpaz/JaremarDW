-- 055: merge Bronze -> Silver para dimSoliscloudStations.

CREATE OR ALTER PROCEDURE [int].usp_MergeDimSoliscloudStations
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.dimSoliscloudStations);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH StgDeduplicado AS (
        SELECT s.*,
               ROW_NUMBER() OVER (PARTITION BY RTRIM(s.StationId) ORDER BY (SELECT NULL)) AS rn
        FROM stg.dimSoliscloudStations s
        WHERE RTRIM(ISNULL(s.StationId, '')) <> ''
    ),
    StgNormalizado AS (
        SELECT
            RTRIM(s.StationId)                     AS StationId,
            NULLIF(RTRIM(s.StationName), '')       AS StationName,
            NULLIF(RTRIM(s.Addr), '')               AS Addr,
            NULLIF(RTRIM(s.Country), '')            AS Country,
            s.TimeZone,
            TRY_CONVERT(DATETIME2(3), DATEADD(SECOND, s.CreateDate / 1000, '1970-01-01')) AS CreateDate
        FROM StgDeduplicado s
        WHERE s.rn = 1
    ),
    StgConHash AS (
        SELECT
            n.*,
            HASHBYTES('SHA2_256', (SELECT n.* FOR XML RAW, BINARY BASE64)) AS HashDiff
        FROM StgNormalizado n
    )
    MERGE [int].dimSoliscloudStations AS destino
        USING StgConHash AS origen
        ON destino.StationId = origen.StationId
    WHEN MATCHED AND destino.HashDiff <> origen.HashDiff THEN
        UPDATE SET
            StationName   = origen.StationName,
            Addr          = origen.Addr,
            Country       = origen.Country,
            TimeZone      = origen.TimeZone,
            CreateDate    = origen.CreateDate,
            EsVigente     = 1,
            HashDiff      = origen.HashDiff,
            FechaCargaInt = SYSDATETIME(),
            RunId         = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (StationId, StationName, Addr, Country, TimeZone, CreateDate, HashDiff, RunId)
        VALUES (origen.StationId, origen.StationName, origen.Addr, origen.Country, origen.TimeZone,
                origen.CreateDate, origen.HashDiff, @RunId)
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

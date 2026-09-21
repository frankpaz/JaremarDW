-- 024: merge Bronze -> Silver para dimCentroCosto.

CREATE OR ALTER PROCEDURE [int].usp_MergeDimCentroCosto
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.dimCentroCosto);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH StgDeduplicado AS (
        SELECT s.*,
               ROW_NUMBER() OVER (PARTITION BY RTRIM(s.SVSGVL) ORDER BY s.SVDATE DESC, s.SVTIME DESC) AS rn
        FROM stg.dimCentroCosto s
        WHERE RTRIM(ISNULL(s.SVSGVL, '')) <> ''
    ),
    StgNormalizado AS (
        SELECT
            RTRIM(s.SVSGVL)                                           AS SVSGVL,
            NULLIF(RTRIM(s.SVID), '')                                 AS SVID,
            NULLIF(RTRIM(s.SVLDES), '')                                AS SVLDES,
            TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(s.SVDATE AS BIGINT)))  AS SVDATE,
            TRY_CONVERT(TIME(0), STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(6), CAST(s.SVTIME AS BIGINT)), 6), 3, 0, ':'), 6, 0, ':')) AS SVTIME
        FROM StgDeduplicado s
        WHERE s.rn = 1
    ),
    StgConHash AS (
        SELECT
            n.*,
            HASHBYTES('SHA2_256', (SELECT n.* FOR XML RAW, BINARY BASE64)) AS HashDiff
        FROM StgNormalizado n
    )
    MERGE [int].dimCentroCosto AS destino
        USING StgConHash AS origen
        ON destino.SVSGVL = origen.SVSGVL
    WHEN MATCHED AND destino.HashDiff <> origen.HashDiff THEN
        UPDATE SET
            SVID          = origen.SVID,
            SVLDES        = origen.SVLDES,
            SVDATE        = origen.SVDATE,
            SVTIME        = origen.SVTIME,
            EsVigente     = 1,
            HashDiff      = origen.HashDiff,
            FechaCargaInt = SYSDATETIME(),
            RunId         = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (SVSGVL, SVID, SVLDES, SVDATE, SVTIME, HashDiff, RunId)
        VALUES (origen.SVSGVL, origen.SVID, origen.SVLDES, origen.SVDATE, origen.SVTIME, origen.HashDiff, @RunId)
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

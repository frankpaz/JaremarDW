-- 271: merge Bronze -> Silver para dimUbicacion. Lo que deja de venir en ILM queda
-- con EsVigente = 0 (nunca se borra).

CREATE OR ALTER PROCEDURE [int].usp_MergeDimUbicacion
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.dimUbicacion);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH StgDeduplicado AS (
        SELECT s.*,
               ROW_NUMBER() OVER (PARTITION BY LTRIM(RTRIM(s.WWHS)), LTRIM(RTRIM(ISNULL(s.WLOC, '')))
                                  ORDER BY s.WID) AS rn
        FROM stg.dimUbicacion s
        WHERE LTRIM(RTRIM(ISNULL(s.WWHS, ''))) <> ''
    ),
    StgNormalizado AS (
        SELECT
            LTRIM(RTRIM(s.WWHS))                                      AS WWHS,
            LTRIM(RTRIM(ISNULL(s.WLOC, '')))                          AS WLOC,
            NULLIF(RTRIM(s.WID), '')                                  AS WID,
            NULLIF(RTRIM(s.WDESC), '')                                AS WDESC,
            s.WCYCI                                                   AS WCYCI,
            NULLIF(LTRIM(RTRIM(s.LMPRF)), '')                         AS LMPRF,
            NULLIF(RTRIM(s.WLTYP), '')                                AS WLTYP,
            NULLIF(RTRIM(s.WZONE), '')                                AS WZONE,
            s.WCONC                                                   AS WCONC,
            NULLIF(RTRIM(s.WALLC), '')                                AS WALLC,
            NULLIF(RTRIM(s.WFLOC), '')                                AS WFLOC
        FROM StgDeduplicado s
        WHERE s.rn = 1
    ),
    StgConHash AS (
        SELECT
            n.*,
            HASHBYTES('SHA2_256', (SELECT n.* FOR XML RAW, BINARY BASE64)) AS HashDiff
        FROM StgNormalizado n
    )
    MERGE [int].dimUbicacion AS destino
        USING StgConHash AS origen
        ON destino.WWHS = origen.WWHS AND destino.WLOC = origen.WLOC
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente = 0) THEN
        UPDATE SET
            WID           = origen.WID,
            WDESC         = origen.WDESC,
            WCYCI         = origen.WCYCI,
            LMPRF         = origen.LMPRF,
            WLTYP         = origen.WLTYP,
            WZONE         = origen.WZONE,
            WCONC         = origen.WCONC,
            WALLC         = origen.WALLC,
            WFLOC         = origen.WFLOC,
            EsVigente     = 1,
            HashDiff      = origen.HashDiff,
            FechaCargaInt = SYSDATETIME(),
            RunId         = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (WWHS, WLOC, WID, WDESC, WCYCI, LMPRF, WLTYP, WZONE, WCONC, WALLC, WFLOC, HashDiff, RunId)
        VALUES (origen.WWHS, origen.WLOC, origen.WID, origen.WDESC, origen.WCYCI, origen.LMPRF, origen.WLTYP,
                origen.WZONE, origen.WCONC, origen.WALLC, origen.WFLOC, origen.HashDiff, @RunId)
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

-- 266: merge Bronze -> Silver para dimAlmacen. Lo que deja de venir en IWM queda
-- con EsVigente = 0 (nunca se borra).

CREATE OR ALTER PROCEDURE [int].usp_MergeDimAlmacen
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.dimAlmacen);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH StgDeduplicado AS (
        SELECT s.*,
               ROW_NUMBER() OVER (PARTITION BY LTRIM(RTRIM(s.LWHS)) ORDER BY s.WFLDTE DESC, s.WFLTME DESC) AS rn
        FROM stg.dimAlmacen s
        WHERE LTRIM(RTRIM(ISNULL(s.LWHS, ''))) <> ''
    ),
    StgFechas AS (
        SELECT d.*,
               TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(NULLIF(d.LLDTE, 0) AS BIGINT)))  AS FechaUltTrans,
               TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(NULLIF(d.WFLDTE, 0) AS BIGINT))) AS FechaMod,
               TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(NULLIF(d.WMCDT, 0) AS BIGINT)))  AS FechaCrea
        FROM StgDeduplicado d
        WHERE d.rn = 1
    ),
    StgNormalizado AS (
        SELECT
            LTRIM(RTRIM(s.LWHS))                                      AS LWHS,
            NULLIF(RTRIM(s.LID), '')                                  AS LID,
            NULLIF(RTRIM(s.LDESC), '')                                AS LDESC,
            s.FechaUltTrans                                           AS LLDTE,
            NULLIF(RTRIM(s.LADD1), '')                                AS LADD1,
            NULLIF(RTRIM(s.LADD2), '')                                AS LADD2,
            NULLIF(RTRIM(s.LADD3), '')                                AS LADD3,
            NULLIF(LTRIM(RTRIM(s.LCOUN)), '')                         AS LCOUN,
            NULLIF(RTRIM(s.LPHON), '')                                AS LPHON,
            NULLIF(RTRIM(s.LALWH), '')                                AS LALWH,
            NULLIF(RTRIM(s.LPOAS), '')                                AS LPOAS,
            NULLIF(RTRIM(s.LNETW), '')                                AS LNETW,
            s.WMCOMP                                                  AS WMCOMP,
            NULLIF(RTRIM(s.WMNCST), '')                               AS WMNCST,
            NULLIF(RTRIM(s.LFRFG), '')                                AS LFRFG,
            NULLIF(RTRIM(s.WMFAC), '')                                AS WMFAC,
            s.WMDYP                                                   AS WMDYP,
            s.WMDYM                                                   AS WMDYM,
            s.WMTYP                                                   AS WMTYP,
            s.WMTYM                                                   AS WMTYM,
            NULLIF(RTRIM(s.WMAUTO), '')                               AS WMAUTO,
            NULLIF(RTRIM(s.WMRLOC), '')                               AS WMRLOC,
            NULLIF(RTRIM(s.WMLUSR), '')                               AS WMLUSR,
            s.FechaMod                                                AS WFLDTE,
            CASE WHEN s.FechaMod IS NOT NULL THEN
                TRY_CONVERT(TIME(0), STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(8), CAST(s.WFLTME AS BIGINT)), 6), 3, 0, ':'), 6, 0, ':'))
            END                                                       AS WFLTME,
            NULLIF(RTRIM(s.WMFAXN), '')                               AS WMFAXN,
            NULLIF(RTRIM(s.WMCBY), '')                                AS WMCBY,
            s.FechaCrea                                               AS WMCDT,
            CASE WHEN s.FechaCrea IS NOT NULL THEN
                TRY_CONVERT(TIME(0), STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(8), CAST(s.WMCTM AS BIGINT)), 6), 3, 0, ':'), 6, 0, ':'))
            END                                                       AS WMCTM,
            NULLIF(RTRIM(s.WMSTE), '')                                AS WMSTE,
            NULLIF(RTRIM(s.WMSLOC), '')                               AS WMSLOC,
            NULLIF(RTRIM(s.WMLANG), '')                               AS WMLANG,
            s.WMMNWH                                                  AS WMMNWH,
            s.WMALRQ                                                  AS WMALRQ
        FROM StgFechas s
    ),
    StgConHash AS (
        SELECT
            n.*,
            HASHBYTES('SHA2_256', (SELECT n.* FOR XML RAW, BINARY BASE64)) AS HashDiff
        FROM StgNormalizado n
    )
    MERGE [int].dimAlmacen AS destino
        USING StgConHash AS origen
        ON destino.LWHS = origen.LWHS
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente = 0) THEN
        UPDATE SET
            LID           = origen.LID,
            LDESC         = origen.LDESC,
            LLDTE         = origen.LLDTE,
            LADD1         = origen.LADD1,
            LADD2         = origen.LADD2,
            LADD3         = origen.LADD3,
            LCOUN         = origen.LCOUN,
            LPHON         = origen.LPHON,
            LALWH         = origen.LALWH,
            LPOAS         = origen.LPOAS,
            LNETW         = origen.LNETW,
            WMCOMP        = origen.WMCOMP,
            WMNCST        = origen.WMNCST,
            LFRFG         = origen.LFRFG,
            WMFAC         = origen.WMFAC,
            WMDYP         = origen.WMDYP,
            WMDYM         = origen.WMDYM,
            WMTYP         = origen.WMTYP,
            WMTYM         = origen.WMTYM,
            WMAUTO        = origen.WMAUTO,
            WMRLOC        = origen.WMRLOC,
            WMLUSR        = origen.WMLUSR,
            WFLDTE        = origen.WFLDTE,
            WFLTME        = origen.WFLTME,
            WMFAXN        = origen.WMFAXN,
            WMCBY         = origen.WMCBY,
            WMCDT         = origen.WMCDT,
            WMCTM         = origen.WMCTM,
            WMSTE         = origen.WMSTE,
            WMSLOC        = origen.WMSLOC,
            WMLANG        = origen.WMLANG,
            WMMNWH        = origen.WMMNWH,
            WMALRQ        = origen.WMALRQ,
            EsVigente     = 1,
            HashDiff      = origen.HashDiff,
            FechaCargaInt = SYSDATETIME(),
            RunId         = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (LWHS, LID, LDESC, LLDTE, LADD1, LADD2, LADD3, LCOUN, LPHON, LALWH, LPOAS, LNETW, WMCOMP, WMNCST,
                LFRFG, WMFAC, WMDYP, WMDYM, WMTYP, WMTYM, WMAUTO, WMRLOC, WMLUSR, WFLDTE, WFLTME, WMFAXN, WMCBY,
                WMCDT, WMCTM, WMSTE, WMSLOC, WMLANG, WMMNWH, WMALRQ, HashDiff, RunId)
        VALUES (origen.LWHS, origen.LID, origen.LDESC, origen.LLDTE, origen.LADD1, origen.LADD2, origen.LADD3,
                origen.LCOUN, origen.LPHON, origen.LALWH, origen.LPOAS, origen.LNETW, origen.WMCOMP, origen.WMNCST,
                origen.LFRFG, origen.WMFAC, origen.WMDYP, origen.WMDYM, origen.WMTYP, origen.WMTYM, origen.WMAUTO,
                origen.WMRLOC, origen.WMLUSR, origen.WFLDTE, origen.WFLTME, origen.WMFAXN, origen.WMCBY, origen.WMCDT,
                origen.WMCTM, origen.WMSTE, origen.WMSLOC, origen.WMLANG, origen.WMMNWH, origen.WMALRQ,
                origen.HashDiff, @RunId)
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

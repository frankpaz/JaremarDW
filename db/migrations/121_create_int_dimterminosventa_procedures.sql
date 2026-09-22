-- 121: merge Bronze -> Silver para dimTerminosVenta.

CREATE OR ALTER PROCEDURE [int].usp_MergeDimTerminosVenta
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.dimTerminosVenta);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH StgDeduplicado AS (
        SELECT s.*,
               ROW_NUMBER() OVER (PARTITION BY s.TMCMPN, s.TMTERM ORDER BY (SELECT NULL)) AS rn
        FROM stg.dimTerminosVenta s
        WHERE s.TMCMPN IS NOT NULL AND RTRIM(ISNULL(s.TMTERM, '')) <> ''
    ),
    StgNormalizado AS (
        SELECT
            s.TMCMPN                                                       AS TMCMPN,
            RTRIM(s.TMTERM)                                                AS TMTERM,
            NULLIF(RTRIM(s.TMDESC), '')                                    AS TMDESC,
            s.TMDUE                                                        AS TMDUE,
            NULLIF(RTRIM(s.TMTAXD), '')                                    AS TMTAXD,
            NULLIF(RTRIM(s.TMBBTA), '')                                    AS TMBBTA,
            NULLIF(RTRIM(s.TMCWO), '')                                     AS TMCWO
        FROM StgDeduplicado s
        WHERE s.rn = 1
    ),
    StgConHash AS (
        SELECT
            n.*,
            HASHBYTES('SHA2_256', (SELECT n.* FOR XML RAW, BINARY BASE64)) AS HashDiff
        FROM StgNormalizado n
    )
    MERGE [int].dimTerminosVenta AS destino
        USING StgConHash AS origen
        ON destino.TMCMPN = origen.TMCMPN AND destino.TMTERM = origen.TMTERM
    WHEN MATCHED AND destino.HashDiff <> origen.HashDiff THEN
        UPDATE SET
            TMDESC        = origen.TMDESC,
            TMDUE         = origen.TMDUE,
            TMTAXD        = origen.TMTAXD,
            TMBBTA        = origen.TMBBTA,
            TMCWO         = origen.TMCWO,
            EsVigente     = 1,
            HashDiff      = origen.HashDiff,
            FechaCargaInt = SYSDATETIME(),
            RunId         = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (TMCMPN, TMTERM, TMDESC, TMDUE, TMTAXD, TMBBTA, TMCWO, HashDiff, RunId)
        VALUES (origen.TMCMPN, origen.TMTERM, origen.TMDESC, origen.TMDUE, origen.TMTAXD, origen.TMBBTA, origen.TMCWO, origen.HashDiff, @RunId)
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

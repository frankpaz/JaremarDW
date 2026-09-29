-- 192: merge Bronze -> Silver para dimTipoBoleta.

CREATE OR ALTER PROCEDURE [int].usp_MergeDimTipoBoleta
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.dimTipoBoleta);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH StgDeduplicado AS (
        SELECT s.*,
               ROW_NUMBER() OVER (PARTITION BY s.BOLETY ORDER BY s.FechaCargaStg DESC) AS rn
        FROM stg.dimTipoBoleta s
        WHERE s.BOLETY IS NOT NULL
    ),
    StgNormalizado AS (
        SELECT
            CAST(s.BOLETY AS INT)                    AS BOLETY,
            NULLIF(RTRIM(s.DESTYP), '')              AS DESTYP,
            NULLIF(RTRIM(s.BENVIO), '')              AS BENVIO,
            NULLIF(RTRIM(s.BINOUT), '')              AS BINOUT,
            CAST(s.BTOLEP AS DECIMAL(6,3))           AS BTOLEP,
            CAST(s.BTOLEN AS DECIMAL(6,3))           AS BTOLEN
        FROM StgDeduplicado s
        WHERE s.rn = 1
    ),
    StgConHash AS (
        SELECT
            n.*,
            HASHBYTES('SHA2_256', (SELECT n.* FOR XML RAW, BINARY BASE64)) AS HashDiff
        FROM StgNormalizado n
    )
    MERGE [int].dimTipoBoleta AS destino
        USING StgConHash AS origen
        ON destino.BOLETY = origen.BOLETY
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente = 0) THEN
        UPDATE SET
            DESTYP        = origen.DESTYP,
            BENVIO        = origen.BENVIO,
            BINOUT        = origen.BINOUT,
            BTOLEP        = origen.BTOLEP,
            BTOLEN        = origen.BTOLEN,
            EsVigente     = 1,
            HashDiff      = origen.HashDiff,
            FechaCargaInt = SYSDATETIME(),
            RunId         = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (BOLETY, DESTYP, BENVIO, BINOUT, BTOLEP, BTOLEN, HashDiff, RunId)
        VALUES (origen.BOLETY, origen.DESTYP, origen.BENVIO, origen.BINOUT, origen.BTOLEP, origen.BTOLEN, origen.HashDiff, @RunId)
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

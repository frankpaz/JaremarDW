-- 188: merge Bronze -> Silver para dimBascula.

CREATE OR ALTER PROCEDURE [int].usp_MergeDimBascula
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.dimBascula);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH StgDeduplicado AS (
        SELECT s.*,
               ROW_NUMBER() OVER (PARTITION BY s.NUMBAS ORDER BY s.FechaCargaStg DESC) AS rn
        FROM stg.dimBascula s
        WHERE s.NUMBAS IS NOT NULL
    ),
    StgNormalizado AS (
        SELECT
            CAST(s.NUMBAS AS INT)                    AS NUMBAS,
            NULLIF(RTRIM(s.MOMBAS), '')              AS MOMBAS
        FROM StgDeduplicado s
        WHERE s.rn = 1
    ),
    StgConHash AS (
        SELECT
            n.*,
            HASHBYTES('SHA2_256', (SELECT n.* FOR XML RAW, BINARY BASE64)) AS HashDiff
        FROM StgNormalizado n
    )
    MERGE [int].dimBascula AS destino
        USING StgConHash AS origen
        ON destino.NUMBAS = origen.NUMBAS
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente = 0) THEN
        UPDATE SET
            MOMBAS        = origen.MOMBAS,
            EsVigente     = 1,
            HashDiff      = origen.HashDiff,
            FechaCargaInt = SYSDATETIME(),
            RunId         = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (NUMBAS, MOMBAS, HashDiff, RunId)
        VALUES (origen.NUMBAS, origen.MOMBAS, origen.HashDiff, @RunId)
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

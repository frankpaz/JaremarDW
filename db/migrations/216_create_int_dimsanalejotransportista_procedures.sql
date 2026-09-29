-- 216: merge Bronze -> Silver para dimSanAlejoTransportista (dominio SanAlejo). FULL: lo que ya no esta en el
-- origen queda con EsVigente = 0 (nunca se borra).

CREATE OR ALTER PROCEDURE [int].usp_MergeDimSanAlejoTransportista
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.dimSanAlejoTransportista);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH StgNormalizado AS (
        SELECT
            CAST(s.[CODCIA] AS INT) AS [CODCIA],
            CAST(s.[CODTRA] AS INT) AS [CODTRA],
            NULLIF(LTRIM(RTRIM(s.[NOMTRA])), '') AS [NOMTRA],
            CAST(s.[VALKIL] AS DECIMAL(12,4)) AS [VALKIL],
            CAST(s.[PRECIO] AS DECIMAL(12,2)) AS [PRECIO],
            CAST(s.[CODALX] AS INT) AS [CODALX]
        FROM stg.dimSanAlejoTransportista s
        WHERE CAST(s.[CODCIA] AS INT) IS NOT NULL AND CAST(s.[CODTRA] AS INT) IS NOT NULL
    ),
    StgDeduplicado AS (
        SELECT n.*, ROW_NUMBER() OVER (PARTITION BY [CODCIA], [CODTRA] ORDER BY [NOMTRA] DESC) AS rn
        FROM StgNormalizado n
    ),
    StgConHash AS (
        SELECT
            u.*,
            HASHBYTES('SHA2_256', (SELECT u.* FOR XML RAW, BINARY BASE64)) AS HashDiff
        FROM (SELECT [CODCIA], [CODTRA], [NOMTRA], [VALKIL], [PRECIO], [CODALX] FROM StgDeduplicado WHERE rn = 1) u
    )
    MERGE [int].dimSanAlejoTransportista AS destino
        USING StgConHash AS origen
        ON destino.[CODCIA] = origen.[CODCIA] AND destino.[CODTRA] = origen.[CODTRA]
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente = 0) THEN
        UPDATE SET
            [NOMTRA]   = origen.[NOMTRA],
            [VALKIL]   = origen.[VALKIL],
            [PRECIO]   = origen.[PRECIO],
            [CODALX]   = origen.[CODALX],
            EsVigente  = 1,
            HashDiff   = origen.HashDiff,
            FechaCargaInt = SYSDATETIME(),
            RunId      = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT ([CODCIA], [CODTRA], [NOMTRA], [VALKIL], [PRECIO], [CODALX], HashDiff, RunId)
        VALUES (origen.[CODCIA], origen.[CODTRA], origen.[NOMTRA], origen.[VALKIL], origen.[PRECIO], origen.[CODALX], origen.HashDiff, @RunId)
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

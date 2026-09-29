-- 228: merge Bronze -> Silver para dimSanAlejoFinca (dominio SanAlejo). FULL: lo que ya no esta en el
-- origen queda con EsVigente = 0 (nunca se borra).

CREATE OR ALTER PROCEDURE [int].usp_MergeDimSanAlejoFinca
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.dimSanAlejoFinca);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH StgNormalizado AS (
        SELECT
            CAST(s.[CODCIA] AS INT) AS [CODCIA],
            NULLIF(LTRIM(RTRIM(s.[FINCA])), '') AS [FINCA],
            CAST(s.[CODSUC] AS INT) AS [CODSUC],
            NULLIF(LTRIM(RTRIM(s.[FRENTE])), '') AS [FRENTE],
            CAST(s.[EXTEN] AS DECIMAL(10,3)) AS [EXTEN],
            NULLIF(LTRIM(RTRIM(s.[DESFIN])), '') AS [DESFIN],
            NULLIF(LTRIM(RTRIM(s.[VARIED])), '') AS [VARIED],
            CAST(s.[PREFFB] AS DECIMAL(13,2)) AS [PREFFB],
            NULLIF(LTRIM(RTRIM(s.[NOPLA])), '') AS [NOPLA],
            CAST(s.[CIAREL] AS INT) AS [CIAREL],
            NULLIF(LTRIM(RTRIM(s.[STATUS])), '') AS [STATUS]
        FROM stg.dimSanAlejoFinca s
        WHERE CAST(s.[CODCIA] AS INT) IS NOT NULL AND NULLIF(LTRIM(RTRIM(s.[FINCA])), '') IS NOT NULL
    ),
    StgDeduplicado AS (
        SELECT n.*, ROW_NUMBER() OVER (PARTITION BY [CODCIA], [FINCA] ORDER BY [CODSUC] DESC) AS rn
        FROM StgNormalizado n
    ),
    StgConHash AS (
        SELECT
            u.*,
            HASHBYTES('SHA2_256', (SELECT u.* FOR XML RAW, BINARY BASE64)) AS HashDiff
        FROM (SELECT [CODCIA], [FINCA], [CODSUC], [FRENTE], [EXTEN], [DESFIN], [VARIED], [PREFFB], [NOPLA], [CIAREL], [STATUS] FROM StgDeduplicado WHERE rn = 1) u
    )
    MERGE [int].dimSanAlejoFinca AS destino
        USING StgConHash AS origen
        ON destino.[CODCIA] = origen.[CODCIA] AND destino.[FINCA] = origen.[FINCA]
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente = 0) THEN
        UPDATE SET
            [CODSUC]   = origen.[CODSUC],
            [FRENTE]   = origen.[FRENTE],
            [EXTEN]    = origen.[EXTEN],
            [DESFIN]   = origen.[DESFIN],
            [VARIED]   = origen.[VARIED],
            [PREFFB]   = origen.[PREFFB],
            [NOPLA]    = origen.[NOPLA],
            [CIAREL]   = origen.[CIAREL],
            [STATUS]   = origen.[STATUS],
            EsVigente  = 1,
            HashDiff   = origen.HashDiff,
            FechaCargaInt = SYSDATETIME(),
            RunId      = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT ([CODCIA], [FINCA], [CODSUC], [FRENTE], [EXTEN], [DESFIN], [VARIED], [PREFFB], [NOPLA], [CIAREL], [STATUS], HashDiff, RunId)
        VALUES (origen.[CODCIA], origen.[FINCA], origen.[CODSUC], origen.[FRENTE], origen.[EXTEN], origen.[DESFIN], origen.[VARIED], origen.[PREFFB], origen.[NOPLA], origen.[CIAREL], origen.[STATUS], origen.HashDiff, @RunId)
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

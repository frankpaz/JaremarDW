-- 220: merge Bronze -> Silver para dimSanAlejoCliente (dominio SanAlejo). FULL: lo que ya no esta en el
-- origen queda con EsVigente = 0 (nunca se borra).

CREATE OR ALTER PROCEDURE [int].usp_MergeDimSanAlejoCliente
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.dimSanAlejoCliente);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH StgNormalizado AS (
        SELECT
            CAST(s.[CODCIA] AS INT) AS [CODCIA],
            CAST(s.[CODCLI] AS INT) AS [CODCLI],
            NULLIF(LTRIM(RTRIM(s.[NOMCLI])), '') AS [NOMCLI],
            NULLIF(LTRIM(RTRIM(s.[DIRCLI])), '') AS [DIRCLI]
        FROM stg.dimSanAlejoCliente s
        WHERE CAST(s.[CODCIA] AS INT) IS NOT NULL AND CAST(s.[CODCLI] AS INT) IS NOT NULL
    ),
    StgDeduplicado AS (
        SELECT n.*, ROW_NUMBER() OVER (PARTITION BY [CODCIA], [CODCLI] ORDER BY [NOMCLI] DESC) AS rn
        FROM StgNormalizado n
    ),
    StgConHash AS (
        SELECT
            u.*,
            HASHBYTES('SHA2_256', (SELECT u.* FOR XML RAW, BINARY BASE64)) AS HashDiff
        FROM (SELECT [CODCIA], [CODCLI], [NOMCLI], [DIRCLI] FROM StgDeduplicado WHERE rn = 1) u
    )
    MERGE [int].dimSanAlejoCliente AS destino
        USING StgConHash AS origen
        ON destino.[CODCIA] = origen.[CODCIA] AND destino.[CODCLI] = origen.[CODCLI]
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente = 0) THEN
        UPDATE SET
            [NOMCLI]   = origen.[NOMCLI],
            [DIRCLI]   = origen.[DIRCLI],
            EsVigente  = 1,
            HashDiff   = origen.HashDiff,
            FechaCargaInt = SYSDATETIME(),
            RunId      = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT ([CODCIA], [CODCLI], [NOMCLI], [DIRCLI], HashDiff, RunId)
        VALUES (origen.[CODCIA], origen.[CODCLI], origen.[NOMCLI], origen.[DIRCLI], origen.HashDiff, @RunId)
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

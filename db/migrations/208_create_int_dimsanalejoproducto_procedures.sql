-- 208: merge Bronze -> Silver para dimSanAlejoProducto (dominio SanAlejo). FULL: lo que ya no esta en el
-- origen queda con EsVigente = 0 (nunca se borra).

CREATE OR ALTER PROCEDURE [int].usp_MergeDimSanAlejoProducto
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.dimSanAlejoProducto);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH StgNormalizado AS (
        SELECT
            NULLIF(LTRIM(RTRIM(s.[COPROD])), '') AS [COPROD],
            NULLIF(LTRIM(RTRIM(s.[NOPROD])), '') AS [NOPROD],
            NULLIF(LTRIM(RTRIM(s.[CODALT])), '') AS [CODALT],
            NULLIF(LTRIM(RTRIM(s.[UNIMED])), '') AS [UNIMED],
            CAST(s.[PREPRO] AS DECIMAL(15,4)) AS [PREPRO],
            NULLIF(LTRIM(RTRIM(s.[CERTIF])), '') AS [CERTIF]
        FROM stg.dimSanAlejoProducto s
        WHERE NULLIF(LTRIM(RTRIM(s.[COPROD])), '') IS NOT NULL
    ),
    StgDeduplicado AS (
        SELECT n.*, ROW_NUMBER() OVER (PARTITION BY [COPROD] ORDER BY [NOPROD] DESC) AS rn
        FROM StgNormalizado n
    ),
    StgConHash AS (
        SELECT
            u.*,
            HASHBYTES('SHA2_256', (SELECT u.* FOR XML RAW, BINARY BASE64)) AS HashDiff
        FROM (SELECT [COPROD], [NOPROD], [CODALT], [UNIMED], [PREPRO], [CERTIF] FROM StgDeduplicado WHERE rn = 1) u
    )
    MERGE [int].dimSanAlejoProducto AS destino
        USING StgConHash AS origen
        ON destino.[COPROD] = origen.[COPROD]
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente = 0) THEN
        UPDATE SET
            [NOPROD]   = origen.[NOPROD],
            [CODALT]   = origen.[CODALT],
            [UNIMED]   = origen.[UNIMED],
            [PREPRO]   = origen.[PREPRO],
            [CERTIF]   = origen.[CERTIF],
            EsVigente  = 1,
            HashDiff   = origen.HashDiff,
            FechaCargaInt = SYSDATETIME(),
            RunId      = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT ([COPROD], [NOPROD], [CODALT], [UNIMED], [PREPRO], [CERTIF], HashDiff, RunId)
        VALUES (origen.[COPROD], origen.[NOPROD], origen.[CODALT], origen.[UNIMED], origen.[PREPRO], origen.[CERTIF], origen.HashDiff, @RunId)
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

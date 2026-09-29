-- 224: merge Bronze -> Silver para dimSanAlejoProductor (dominio SanAlejo). FULL: lo que ya no esta en el
-- origen queda con EsVigente = 0 (nunca se borra).

CREATE OR ALTER PROCEDURE [int].usp_MergeDimSanAlejoProductor
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.dimSanAlejoProductor);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH StgNormalizado AS (
        SELECT
            CAST(s.[CODCIA] AS INT) AS [CODCIA],
            CAST(s.[CODPRO] AS INT) AS [CODPRO],
            NULLIF(LTRIM(RTRIM(s.[NOMPRO])), '') AS [NOMPRO],
            NULLIF(LTRIM(RTRIM(s.[UBICA])), '') AS [UBICA],
            NULLIF(LTRIM(RTRIM(s.[SECTOR])), '') AS [SECTOR],
            CAST(s.[ESTADO] AS INT) AS [ESTADO],
            CAST(s.[TOTHEC] AS DECIMAL(10,3)) AS [TOTHEC],
            CAST(NULLIF(s.[NUMCON], 0) AS BIGINT) AS [NUMCON],
            TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(NULLIF(s.[FECCON], 0) AS BIGINT))) AS [FECCON],
            TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(NULLIF(s.[FECFIN], 0) AS BIGINT))) AS [FECFIN],
            CAST(s.[CODLOC] AS INT) AS [CODLOC],
            CAST(s.[CODANT] AS INT) AS [CODANT]
        FROM stg.dimSanAlejoProductor s
        WHERE CAST(s.[CODCIA] AS INT) IS NOT NULL AND CAST(s.[CODPRO] AS INT) IS NOT NULL
    ),
    StgDeduplicado AS (
        SELECT n.*, ROW_NUMBER() OVER (PARTITION BY [CODCIA], [CODPRO] ORDER BY [NOMPRO] DESC) AS rn
        FROM StgNormalizado n
    ),
    StgConHash AS (
        SELECT
            u.*,
            HASHBYTES('SHA2_256', (SELECT u.* FOR XML RAW, BINARY BASE64)) AS HashDiff
        FROM (SELECT [CODCIA], [CODPRO], [NOMPRO], [UBICA], [SECTOR], [ESTADO], [TOTHEC], [NUMCON], [FECCON], [FECFIN], [CODLOC], [CODANT] FROM StgDeduplicado WHERE rn = 1) u
    )
    MERGE [int].dimSanAlejoProductor AS destino
        USING StgConHash AS origen
        ON destino.[CODCIA] = origen.[CODCIA] AND destino.[CODPRO] = origen.[CODPRO]
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente = 0) THEN
        UPDATE SET
            [NOMPRO]   = origen.[NOMPRO],
            [UBICA]    = origen.[UBICA],
            [SECTOR]   = origen.[SECTOR],
            [ESTADO]   = origen.[ESTADO],
            [TOTHEC]   = origen.[TOTHEC],
            [NUMCON]   = origen.[NUMCON],
            [FECCON]   = origen.[FECCON],
            [FECFIN]   = origen.[FECFIN],
            [CODLOC]   = origen.[CODLOC],
            [CODANT]   = origen.[CODANT],
            EsVigente  = 1,
            HashDiff   = origen.HashDiff,
            FechaCargaInt = SYSDATETIME(),
            RunId      = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT ([CODCIA], [CODPRO], [NOMPRO], [UBICA], [SECTOR], [ESTADO], [TOTHEC], [NUMCON], [FECCON], [FECFIN], [CODLOC], [CODANT], HashDiff, RunId)
        VALUES (origen.[CODCIA], origen.[CODPRO], origen.[NOMPRO], origen.[UBICA], origen.[SECTOR], origen.[ESTADO], origen.[TOTHEC], origen.[NUMCON], origen.[FECCON], origen.[FECFIN], origen.[CODLOC], origen.[CODANT], origen.HashDiff, @RunId)
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

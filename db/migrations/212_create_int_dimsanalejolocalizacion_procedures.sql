-- 212: merge Bronze -> Silver para dimSanAlejoLocalizacion (dominio SanAlejo). FULL: lo que ya no esta en el
-- origen queda con EsVigente = 0 (nunca se borra).

CREATE OR ALTER PROCEDURE [int].usp_MergeDimSanAlejoLocalizacion
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.dimSanAlejoLocalizacion);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH StgNormalizado AS (
        SELECT
            CAST(s.[CODCIA] AS INT) AS [CODCIA],
            CAST(s.[CODLOC] AS INT) AS [CODLOC],
            NULLIF(LTRIM(RTRIM(s.[ORIGEN])), '') AS [ORIGEN],
            NULLIF(LTRIM(RTRIM(s.[DESTIN])), '') AS [DESTIN],
            CAST(s.[PRECTM] AS DECIMAL(13,4)) AS [PRECTM],
            CAST(s.[COSTOK] AS DECIMAL(13,4)) AS [COSTOK],
            NULLIF(LTRIM(RTRIM(s.[CODTAR])), '') AS [CODTAR],
            NULLIF(LTRIM(RTRIM(s.[SECTOR])), '') AS [SECTOR],
            NULLIF(LTRIM(RTRIM(s.[CAMPO1])), '') AS [CAMPO1],
            NULLIF(LTRIM(RTRIM(s.[MARCA])), '') AS [MARCA]
        FROM stg.dimSanAlejoLocalizacion s
        WHERE CAST(s.[CODCIA] AS INT) IS NOT NULL AND CAST(s.[CODLOC] AS INT) IS NOT NULL
    ),
    StgDeduplicado AS (
        SELECT n.*, ROW_NUMBER() OVER (PARTITION BY [CODCIA], [CODLOC] ORDER BY [ORIGEN] DESC) AS rn
        FROM StgNormalizado n
    ),
    StgConHash AS (
        SELECT
            u.*,
            HASHBYTES('SHA2_256', (SELECT u.* FOR XML RAW, BINARY BASE64)) AS HashDiff
        FROM (SELECT [CODCIA], [CODLOC], [ORIGEN], [DESTIN], [PRECTM], [COSTOK], [CODTAR], [SECTOR], [CAMPO1], [MARCA] FROM StgDeduplicado WHERE rn = 1) u
    )
    MERGE [int].dimSanAlejoLocalizacion AS destino
        USING StgConHash AS origen
        ON destino.[CODCIA] = origen.[CODCIA] AND destino.[CODLOC] = origen.[CODLOC]
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente = 0) THEN
        UPDATE SET
            [ORIGEN]   = origen.[ORIGEN],
            [DESTIN]   = origen.[DESTIN],
            [PRECTM]   = origen.[PRECTM],
            [COSTOK]   = origen.[COSTOK],
            [CODTAR]   = origen.[CODTAR],
            [SECTOR]   = origen.[SECTOR],
            [CAMPO1]   = origen.[CAMPO1],
            [MARCA]    = origen.[MARCA],
            EsVigente  = 1,
            HashDiff   = origen.HashDiff,
            FechaCargaInt = SYSDATETIME(),
            RunId      = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT ([CODCIA], [CODLOC], [ORIGEN], [DESTIN], [PRECTM], [COSTOK], [CODTAR], [SECTOR], [CAMPO1], [MARCA], HashDiff, RunId)
        VALUES (origen.[CODCIA], origen.[CODLOC], origen.[ORIGEN], origen.[DESTIN], origen.[PRECTM], origen.[COSTOK], origen.[CODTAR], origen.[SECTOR], origen.[CAMPO1], origen.[MARCA], origen.HashDiff, @RunId)
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

-- 143: merge Bronze -> Silver para dimRuta. Carga FULL: lo que ya no viene
-- del origen se da de baja (EsVigente = 0), mismo patron que dimSector.

CREATE OR ALTER PROCEDURE [int].usp_MergeDimRuta
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.dimRuta);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH StgDeduplicado AS (
        SELECT s.*,
               ROW_NUMBER() OVER (PARTITION BY RTRIM(s.CCCODE) ORDER BY s.CCMNDT DESC, s.CCMNTM DESC, s.CCENDT DESC) AS rn
        FROM stg.dimRuta s
        WHERE RTRIM(ISNULL(s.CCCODE, '')) <> ''
    ),
    StgNormalizado AS (
        SELECT
            RTRIM(s.CCCODE)                                            AS CCCODE,
            NULLIF(RTRIM(s.CCDESC), '')                                AS CCDESC,
            TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(s.CCENDT AS BIGINT))) AS CCENDT,
            CASE WHEN s.CCENDT > 0
                 THEN TRY_CONVERT(TIME(0), STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(6), CAST(s.CCENTM AS BIGINT)), 6), 3, 0, ':'), 6, 0, ':'))
            END                                                        AS CCENTM,
            NULLIF(RTRIM(s.CCENUS), '')                                AS CCENUS,
            TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(s.CCMNDT AS BIGINT))) AS CCMNDT,
            CASE WHEN s.CCMNDT > 0
                 THEN TRY_CONVERT(TIME(0), STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(6), CAST(s.CCMNTM AS BIGINT)), 6), 3, 0, ':'), 6, 0, ':'))
            END                                                        AS CCMNTM,
            NULLIF(RTRIM(s.CCMNUS), '')                                AS CCMNUS
        FROM StgDeduplicado s
        WHERE s.rn = 1
    ),
    StgConHash AS (
        SELECT
            n.*,
            HASHBYTES('SHA2_256', (SELECT n.* FOR XML RAW, BINARY BASE64)) AS HashDiff
        FROM StgNormalizado n
    )
    MERGE [int].dimRuta AS destino
        USING StgConHash AS origen
        ON destino.CCCODE = origen.CCCODE
    WHEN MATCHED AND destino.HashDiff <> origen.HashDiff THEN
        UPDATE SET
            CCDESC        = origen.CCDESC,
            CCENDT        = origen.CCENDT,
            CCENTM        = origen.CCENTM,
            CCENUS        = origen.CCENUS,
            CCMNDT        = origen.CCMNDT,
            CCMNTM        = origen.CCMNTM,
            CCMNUS        = origen.CCMNUS,
            EsVigente     = 1,
            HashDiff      = origen.HashDiff,
            FechaCargaInt = SYSDATETIME(),
            RunId         = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (CCCODE, CCDESC, CCENDT, CCENTM, CCENUS, CCMNDT, CCMNTM, CCMNUS, HashDiff, RunId)
        VALUES (origen.CCCODE, origen.CCDESC, origen.CCENDT, origen.CCENTM, origen.CCENUS,
                origen.CCMNDT, origen.CCMNTM, origen.CCMNUS, origen.HashDiff, @RunId)
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

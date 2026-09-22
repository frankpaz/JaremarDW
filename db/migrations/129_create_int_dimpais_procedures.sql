-- 129: merge Bronze -> Silver para dimPais.

CREATE OR ALTER PROCEDURE [int].usp_MergeDimPais
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.dimPais);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH StgDeduplicado AS (
        SELECT s.*,
               ROW_NUMBER() OVER (PARTITION BY RTRIM(s.CNCNTY) ORDER BY s.CNCDTE DESC, s.CNCTME DESC) AS rn
        FROM stg.dimPais s
        WHERE RTRIM(ISNULL(s.CNCNTY, '')) <> ''
    ),
    StgNormalizado AS (
        SELECT
            RTRIM(s.CNCNTY)                                                AS CNCNTY,
            NULLIF(RTRIM(s.CNLDSC), '')                                    AS CNLDSC,
            NULLIF(RTRIM(s.CNSDSC), '')                                    AS CNSDSC,
            NULLIF(RTRIM(s.CNLANG), '')                                    AS CNLANG,
            NULLIF(RTRIM(s.CNLUSR), '')                                    AS CNLUSR,
            TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(s.CNLDTE AS BIGINT)))  AS CNLDTE,
            TRY_CONVERT(TIME(0), STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(6), CAST(s.CNLTME AS BIGINT)), 6), 3, 0, ':'), 6, 0, ':')) AS CNLTME,
            NULLIF(RTRIM(s.CNCUSR), '')                                    AS CNCUSR,
            TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(s.CNCDTE AS BIGINT)))  AS CNCDTE,
            TRY_CONVERT(TIME(0), STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(6), CAST(s.CNCTME AS BIGINT)), 6), 3, 0, ':'), 6, 0, ':')) AS CNCTME
        FROM StgDeduplicado s
        WHERE s.rn = 1
    ),
    StgConHash AS (
        SELECT
            n.*,
            HASHBYTES('SHA2_256', (SELECT n.* FOR XML RAW, BINARY BASE64)) AS HashDiff
        FROM StgNormalizado n
    )
    MERGE [int].dimPais AS destino
        USING StgConHash AS origen
        ON destino.CNCNTY = origen.CNCNTY
    WHEN MATCHED AND destino.HashDiff <> origen.HashDiff THEN
        UPDATE SET
            CNLDSC        = origen.CNLDSC,
            CNSDSC        = origen.CNSDSC,
            CNLANG        = origen.CNLANG,
            CNLUSR        = origen.CNLUSR,
            CNLDTE        = origen.CNLDTE,
            CNLTME        = origen.CNLTME,
            CNCUSR        = origen.CNCUSR,
            CNCDTE        = origen.CNCDTE,
            CNCTME        = origen.CNCTME,
            EsVigente     = 1,
            HashDiff      = origen.HashDiff,
            FechaCargaInt = SYSDATETIME(),
            RunId         = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (CNCNTY, CNLDSC, CNSDSC, CNLANG, CNLUSR, CNLDTE, CNLTME, CNCUSR, CNCDTE, CNCTME, HashDiff, RunId)
        VALUES (origen.CNCNTY, origen.CNLDSC, origen.CNSDSC, origen.CNLANG, origen.CNLUSR, origen.CNLDTE, origen.CNLTME, origen.CNCUSR, origen.CNCDTE, origen.CNCTME, origen.HashDiff, @RunId)
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

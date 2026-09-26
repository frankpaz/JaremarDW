-- 168: merge Bronze -> Silver para dimVehiculo.

CREATE OR ALTER PROCEDURE [int].usp_MergeDimVehiculo
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.dimVehiculo);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH StgDeduplicado AS (
        SELECT s.*,
               ROW_NUMBER() OVER (PARTITION BY LTRIM(RTRIM(s.CMCARR)) ORDER BY s.CMLDTE DESC, s.CMLTME DESC) AS rn
        FROM stg.dimVehiculo s
        WHERE LTRIM(RTRIM(ISNULL(s.CMCARR, ''))) <> ''
    ),
    StgFechas AS (
        SELECT d.*,
               TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(NULLIF(d.CMLDTE, 0) AS BIGINT))) AS FechaMod
        FROM StgDeduplicado d
        WHERE d.rn = 1
    ),
    StgNormalizado AS (
        SELECT
            LTRIM(RTRIM(s.CMCARR))                                    AS CMCARR,
            NULLIF(RTRIM(s.CMID), '')                                 AS CMID,
            NULLIF(RTRIM(s.CMCDES), '')                               AS CMCDES,
            NULLIF(RTRIM(s.CMXDES), '')                               AS CMXDES,
            NULLIF(RTRIM(s.CMADR1), '')                               AS CMADR1,
            NULLIF(RTRIM(s.CMADR2), '')                               AS CMADR2,
            NULLIF(RTRIM(s.CMSTCD), '')                               AS CMSTCD,
            NULLIF(RTRIM(s.CMPSCD), '')                               AS CMPSCD,
            NULLIF(LTRIM(RTRIM(s.CMCNTY)), '')                        AS CMCNTY,
            s.CMSHPC                                                  AS CMSHPC,
            s.CMPERR                                                  AS CMPERR,
            s.CMVEND                                                  AS CMVEND,
            NULLIF(RTRIM(s.CMINVF), '')                               AS CMINVF,
            NULLIF(RTRIM(s.CMLUSR), '')                               AS CMLUSR,
            s.FechaMod                                                AS CMLDTE,
            CASE WHEN s.FechaMod IS NOT NULL THEN
                TRY_CONVERT(TIME(0), STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(8), CAST(s.CMLTME AS BIGINT)), 6), 3, 0, ':'), 6, 0, ':'))
            END                                                       AS CMLTME,
            NULLIF(RTRIM(s.CMADR5), '')                               AS CMADR5,
            NULLIF(RTRIM(s.CMADR6), '')                               AS CMADR6,
            NULLIF(RTRIM(s.CMATTN), '')                               AS CMATTN,
            NULLIF(RTRIM(s.CMDATN), '')                               AS CMDATN,
            NULLIF(RTRIM(s.CMPHON), '')                               AS CMPHON,
            NULLIF(RTRIM(s.CMFRCC), '')                               AS CMFRCC
        FROM StgFechas s
    ),
    StgConHash AS (
        SELECT
            n.*,
            HASHBYTES('SHA2_256', (SELECT n.* FOR XML RAW, BINARY BASE64)) AS HashDiff
        FROM StgNormalizado n
    )
    MERGE [int].dimVehiculo AS destino
        USING StgConHash AS origen
        ON destino.CMCARR = origen.CMCARR
    WHEN MATCHED AND destino.HashDiff <> origen.HashDiff THEN
        UPDATE SET
            CMID          = origen.CMID,
            CMCDES        = origen.CMCDES,
            CMXDES        = origen.CMXDES,
            CMADR1        = origen.CMADR1,
            CMADR2        = origen.CMADR2,
            CMSTCD        = origen.CMSTCD,
            CMPSCD        = origen.CMPSCD,
            CMCNTY        = origen.CMCNTY,
            CMSHPC        = origen.CMSHPC,
            CMPERR        = origen.CMPERR,
            CMVEND        = origen.CMVEND,
            CMINVF        = origen.CMINVF,
            CMLUSR        = origen.CMLUSR,
            CMLDTE        = origen.CMLDTE,
            CMLTME        = origen.CMLTME,
            CMADR5        = origen.CMADR5,
            CMADR6        = origen.CMADR6,
            CMATTN        = origen.CMATTN,
            CMDATN        = origen.CMDATN,
            CMPHON        = origen.CMPHON,
            CMFRCC        = origen.CMFRCC,
            EsVigente     = 1,
            HashDiff      = origen.HashDiff,
            FechaCargaInt = SYSDATETIME(),
            RunId         = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (CMCARR, CMID, CMCDES, CMXDES, CMADR1, CMADR2, CMSTCD, CMPSCD, CMCNTY, CMSHPC, CMPERR, CMVEND,
                CMINVF, CMLUSR, CMLDTE, CMLTME, CMADR5, CMADR6, CMATTN, CMDATN, CMPHON, CMFRCC, HashDiff, RunId)
        VALUES (origen.CMCARR, origen.CMID, origen.CMCDES, origen.CMXDES, origen.CMADR1, origen.CMADR2, origen.CMSTCD,
                origen.CMPSCD, origen.CMCNTY, origen.CMSHPC, origen.CMPERR, origen.CMVEND, origen.CMINVF, origen.CMLUSR,
                origen.CMLDTE, origen.CMLTME, origen.CMADR5, origen.CMADR6, origen.CMATTN, origen.CMDATN, origen.CMPHON,
                origen.CMFRCC, origen.HashDiff, @RunId)
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

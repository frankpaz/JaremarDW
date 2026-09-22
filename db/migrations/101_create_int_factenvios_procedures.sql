-- 101: merge Bronze -> Silver para factEnvios. FULL + SCD Tipo 1 (dedup +
-- HashDiff), no incremental por watermark real (ver 100_create_int_factenvios.sql).
-- Dedup por ENCENV, orden ENCFEC DESC, ENCTIM DESC (los 2 duplicados
-- legitimos observados en el origen son doble pesaje el mismo dia -- se
-- conserva el mas reciente por hora).
-- ENCFEC/ENCFEU (DECIMAL YYYYMMDD) -> DATE. ENCTIM/ENCTIU (DECIMAL
-- HHMMSSHH, centesimas de segundo) -> TIME(0), descartando las centesimas
-- (/100 antes de formatear).

CREATE OR ALTER PROCEDURE [int].usp_MergeFactEnvios
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.factEnvios);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH StgDeduplicado AS (
        SELECT s.*,
               ROW_NUMBER() OVER (PARTITION BY s.ENCENV ORDER BY s.ENCFEC DESC, s.ENCTIM DESC) AS rn
        FROM stg.factEnvios s
        WHERE s.ENCENV IS NOT NULL AND s.ENCENV <> 0
    ),
    StgNormalizado AS (
        SELECT
            s.ENCENV                                                       AS ENCENV,
            NULLIF(RTRIM(s.ENCUSU), '')                                    AS ENCUSU,
            NULLIF(RTRIM(s.ENCDSP), '')                                    AS ENCDSP,
            TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(s.ENCFEC AS BIGINT)))  AS ENCFEC,
            TRY_CONVERT(TIME(0), STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(6), CAST(s.ENCTIM AS BIGINT) / 100), 6), 3, 0, ':'), 6, 0, ':')) AS ENCTIM,
            NULLIF(RTRIM(s.ENCCAM), '')                                    AS ENCCAM,
            s.ENCPEC                                                       AS ENCPEC,
            NULLIF(RTRIM(s.ENCCAD), '')                                    AS ENCCAD,
            s.ENCEMT                                                       AS ENCEMT,
            NULLIF(RTRIM(s.ENCEMN), '')                                    AS ENCEMN,
            s.ENCEN1                                                       AS ENCEN1,
            NULLIF(RTRIM(s.ENCED1), '')                                    AS ENCED1,
            s.ENCEN2                                                       AS ENCEN2,
            NULLIF(RTRIM(s.ENCED2), '')                                    AS ENCED2,
            s.ENCEN3                                                       AS ENCEN3,
            NULLIF(RTRIM(s.ENCED3), '')                                    AS ENCED3,
            s.ENCEN4                                                       AS ENCEN4,
            NULLIF(RTRIM(s.ENCED4), '')                                    AS ENCED4,
            NULLIF(RTRIM(s.ENCROU), '')                                    AS ENCROU,
            NULLIF(RTRIM(s.ENCDER), '')                                    AS ENCDER,
            TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(s.ENCFEU AS BIGINT)))  AS ENCFEU,
            TRY_CONVERT(TIME(0), STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(6), CAST(s.ENCTIU AS BIGINT) / 100), 6), 3, 0, ':'), 6, 0, ':')) AS ENCTIU,
            NULLIF(RTRIM(s.ENCSTA), '')                                    AS ENCSTA,
            s.ENCPES                                                       AS ENCPES,
            NULLIF(RTRIM(s.ENCPLA), '')                                    AS ENCPLA,
            NULLIF(RTRIM(s.ENCDT1), '')                                    AS ENCDT1,
            NULLIF(RTRIM(s.ENCPT2), '')                                    AS ENCPT2
        FROM StgDeduplicado s
        WHERE s.rn = 1
    ),
    StgConHash AS (
        SELECT
            n.*,
            HASHBYTES('SHA2_256', (SELECT n.* FOR XML RAW, BINARY BASE64)) AS HashDiff
        FROM StgNormalizado n
    )
    MERGE [int].factEnvios AS destino
        USING StgConHash AS origen
        ON destino.ENCENV = origen.ENCENV
    WHEN MATCHED AND destino.HashDiff <> origen.HashDiff THEN
        UPDATE SET
            ENCUSU        = origen.ENCUSU,
            ENCDSP        = origen.ENCDSP,
            ENCFEC        = origen.ENCFEC,
            ENCTIM        = origen.ENCTIM,
            ENCCAM        = origen.ENCCAM,
            ENCPEC        = origen.ENCPEC,
            ENCCAD        = origen.ENCCAD,
            ENCEMT        = origen.ENCEMT,
            ENCEMN        = origen.ENCEMN,
            ENCEN1        = origen.ENCEN1,
            ENCED1        = origen.ENCED1,
            ENCEN2        = origen.ENCEN2,
            ENCED2        = origen.ENCED2,
            ENCEN3        = origen.ENCEN3,
            ENCED3        = origen.ENCED3,
            ENCEN4        = origen.ENCEN4,
            ENCED4        = origen.ENCED4,
            ENCROU        = origen.ENCROU,
            ENCDER        = origen.ENCDER,
            ENCFEU        = origen.ENCFEU,
            ENCTIU        = origen.ENCTIU,
            ENCSTA        = origen.ENCSTA,
            ENCPES        = origen.ENCPES,
            ENCPLA        = origen.ENCPLA,
            ENCDT1        = origen.ENCDT1,
            ENCPT2        = origen.ENCPT2,
            EsVigente     = 1,
            HashDiff      = origen.HashDiff,
            FechaCargaInt = SYSDATETIME(),
            RunId         = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (
            ENCENV, ENCUSU, ENCDSP, ENCFEC, ENCTIM, ENCCAM, ENCPEC, ENCCAD, ENCEMT, ENCEMN,
            ENCEN1, ENCED1, ENCEN2, ENCED2, ENCEN3, ENCED3, ENCEN4, ENCED4,
            ENCROU, ENCDER, ENCFEU, ENCTIU, ENCSTA, ENCPES, ENCPLA, ENCDT1, ENCPT2,
            HashDiff, RunId
        )
        VALUES (
            origen.ENCENV, origen.ENCUSU, origen.ENCDSP, origen.ENCFEC, origen.ENCTIM, origen.ENCCAM, origen.ENCPEC, origen.ENCCAD, origen.ENCEMT, origen.ENCEMN,
            origen.ENCEN1, origen.ENCED1, origen.ENCEN2, origen.ENCED2, origen.ENCEN3, origen.ENCED3, origen.ENCEN4, origen.ENCED4,
            origen.ENCROU, origen.ENCDER, origen.ENCFEU, origen.ENCTIU, origen.ENCSTA, origen.ENCPES, origen.ENCPLA, origen.ENCDT1, origen.ENCPT2,
            origen.HashDiff, @RunId
        )
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

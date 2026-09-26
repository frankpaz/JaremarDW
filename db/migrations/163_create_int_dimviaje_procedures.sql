-- 163: merge Bronze -> Silver para dimViaje.

CREATE OR ALTER PROCEDURE [int].usp_MergeDimViaje
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.dimViaje);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH StgDeduplicado AS (
        SELECT s.*,
               ROW_NUMBER() OVER (PARTITION BY s.VCODPA ORDER BY s.VFECHM DESC, s.VHORAM DESC) AS rn
        FROM stg.dimViaje s
        WHERE s.VCODPA IS NOT NULL
    ),
    StgFechas AS (
        SELECT d.*,
               TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(NULLIF(d.VFECHG, 0) AS BIGINT))) AS FechaG,
               TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(NULLIF(d.VFECHM, 0) AS BIGINT))) AS FechaM
        FROM StgDeduplicado d
        WHERE d.rn = 1
    ),
    StgNormalizado AS (
        SELECT
            CAST(s.VCODPA AS INT)                                     AS VCODPA,
            NULLIF(RTRIM(s.VDESC), '')                                AS VDESC,
            s.VPAGAM                                                  AS VPAGAM,
            s.VPAGAA                                                  AS VPAGAA,
            NULLIF(RTRIM(s.VUSUAG), '')                               AS VUSUAG,
            s.FechaG                                                  AS VFECHG,
            CASE WHEN s.FechaG IS NOT NULL THEN
                TRY_CONVERT(TIME(0), STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(8), CAST(s.VHORAG AS BIGINT)), 6), 3, 0, ':'), 6, 0, ':'))
            END                                                       AS VHORAG,
            NULLIF(RTRIM(s.VUSUAM), '')                               AS VUSUAM,
            s.FechaM                                                  AS VFECHM,
            CASE WHEN s.FechaM IS NOT NULL THEN
                TRY_CONVERT(TIME(0), STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(8), CAST(s.VHORAM AS BIGINT)), 6), 3, 0, ':'), 6, 0, ':'))
            END                                                       AS VHORAM,
            NULLIF(RTRIM(s.VSTS), '')                                 AS VSTS
        FROM StgFechas s
    ),
    StgConHash AS (
        SELECT
            n.*,
            HASHBYTES('SHA2_256', (SELECT n.* FOR XML RAW, BINARY BASE64)) AS HashDiff
        FROM StgNormalizado n
    )
    MERGE [int].dimViaje AS destino
        USING StgConHash AS origen
        ON destino.VCODPA = origen.VCODPA
    WHEN MATCHED AND destino.HashDiff <> origen.HashDiff THEN
        UPDATE SET
            VDESC         = origen.VDESC,
            VPAGAM        = origen.VPAGAM,
            VPAGAA        = origen.VPAGAA,
            VUSUAG        = origen.VUSUAG,
            VFECHG        = origen.VFECHG,
            VHORAG        = origen.VHORAG,
            VUSUAM        = origen.VUSUAM,
            VFECHM        = origen.VFECHM,
            VHORAM        = origen.VHORAM,
            VSTS          = origen.VSTS,
            EsVigente     = 1,
            HashDiff      = origen.HashDiff,
            FechaCargaInt = SYSDATETIME(),
            RunId         = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (VCODPA, VDESC, VPAGAM, VPAGAA, VUSUAG, VFECHG, VHORAG, VUSUAM, VFECHM, VHORAM, VSTS, HashDiff, RunId)
        VALUES (origen.VCODPA, origen.VDESC, origen.VPAGAM, origen.VPAGAA, origen.VUSUAG, origen.VFECHG, origen.VHORAG,
                origen.VUSUAM, origen.VFECHM, origen.VHORAM, origen.VSTS, origen.HashDiff, @RunId)
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

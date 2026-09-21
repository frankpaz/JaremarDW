-- 008: procedimiento de merge Bronze -> Silver para dimProducto.

CREATE OR ALTER PROCEDURE [int].usp_MergeDimProducto
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.dimProducto);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH StgDeduplicado AS (
        SELECT s.*,
               ROW_NUMBER() OVER (
                   PARTITION BY RTRIM(s.IPROD)
                   ORDER BY s.IMMNDT DESC, s.IMMNTM DESC
               ) AS rn
        FROM stg.dimProducto s
        WHERE RTRIM(ISNULL(s.IPROD, '')) <> ''
    ),
    StgNormalizado AS (
        SELECT
            RTRIM(s.IPROD)                                                      AS IPROD,
            NULLIF(RTRIM(s.IDESC), '')                                          AS IDESC,
            NULLIF(RTRIM(s.ICLAS), '')                                          AS ICLAS,
            NULLIF(RTRIM(s.IUMS), '')                                           AS IUMS,
            NULLIF(RTRIM(s.IUMP), '')                                           AS IUMP,
            TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(s.ILDTE AS BIGINT)))        AS ILDTE,
            TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(s.IMMNDT AS BIGINT)))       AS IMMNDT,
            TRY_CONVERT(TIME(0), STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(6), CAST(s.IMMNTM AS BIGINT)), 6), 3, 0, ':'), 6, 0, ':')) AS IMMNTM
        FROM StgDeduplicado s
        WHERE s.rn = 1
    ),
    StgConHash AS (
        SELECT
            n.*,
            HASHBYTES('SHA2_256', (SELECT n.* FOR XML RAW, BINARY BASE64)) AS HashDiff
        FROM StgNormalizado n
    )
    MERGE [int].dimProducto AS destino
    USING StgConHash AS origen
        ON destino.IPROD = origen.IPROD
    WHEN MATCHED AND destino.HashDiff <> origen.HashDiff THEN
        UPDATE SET
            IDESC         = origen.IDESC,
            ICLAS         = origen.ICLAS,
            IUMS          = origen.IUMS,
            IUMP          = origen.IUMP,
            ILDTE         = origen.ILDTE,
            IMMNDT        = origen.IMMNDT,
            IMMNTM        = origen.IMMNTM,
            EsVigente     = 1,
            HashDiff      = origen.HashDiff,
            FechaCargaInt = SYSDATETIME(),
            RunId         = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (IPROD, IDESC, ICLAS, IUMS, IUMP, ILDTE, IMMNDT, IMMNTM, HashDiff, RunId)
        VALUES (origen.IPROD, origen.IDESC, origen.ICLAS, origen.IUMS, origen.IUMP,
                origen.ILDTE, origen.IMMNDT, origen.IMMNTM, origen.HashDiff, @RunId)
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

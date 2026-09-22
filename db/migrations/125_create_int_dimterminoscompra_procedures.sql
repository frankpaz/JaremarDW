-- 125: merge Bronze -> Silver para dimTerminosCompra.

CREATE OR ALTER PROCEDURE [int].usp_MergeDimTerminosCompra
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.dimTerminosCompra);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH StgDeduplicado AS (
        SELECT s.*,
               ROW_NUMBER() OVER (PARTITION BY RTRIM(s.VTERM) ORDER BY (SELECT NULL)) AS rn
        FROM stg.dimTerminosCompra s
        WHERE RTRIM(ISNULL(s.VTERM, '')) <> ''
    ),
    StgNormalizado AS (
        SELECT
            RTRIM(s.VTERM)                                                 AS VTERM,
            NULLIF(RTRIM(s.VTMDSC), '')                                    AS VTMDSC,
            s.VTMDDY                                                       AS VTMDDY,
            NULLIF(RTRIM(s.VTTAXD), '')                                    AS VTTAXD
        FROM StgDeduplicado s
        WHERE s.rn = 1
    ),
    StgConHash AS (
        SELECT
            n.*,
            HASHBYTES('SHA2_256', (SELECT n.* FOR XML RAW, BINARY BASE64)) AS HashDiff
        FROM StgNormalizado n
    )
    MERGE [int].dimTerminosCompra AS destino
        USING StgConHash AS origen
        ON destino.VTERM = origen.VTERM
    WHEN MATCHED AND destino.HashDiff <> origen.HashDiff THEN
        UPDATE SET
            VTMDSC        = origen.VTMDSC,
            VTMDDY        = origen.VTMDDY,
            VTTAXD        = origen.VTTAXD,
            EsVigente     = 1,
            HashDiff      = origen.HashDiff,
            FechaCargaInt = SYSDATETIME(),
            RunId         = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (VTERM, VTMDSC, VTMDDY, VTTAXD, HashDiff, RunId)
        VALUES (origen.VTERM, origen.VTMDSC, origen.VTMDDY, origen.VTTAXD, origen.HashDiff, @RunId)
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

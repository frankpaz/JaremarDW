-- 036: usp_MergeDimEmpresas ahora enriquece con la moneda funcional, via
-- JOIN contra stg.dimEmpresaMoneda (CMPNY con cero a la izquierda = SVSGVL).
-- El JOIN es LEFT: la compania '02' (consolidacion) no tiene moneda y queda
-- NULL, no se descarta la fila.

CREATE OR ALTER PROCEDURE [int].usp_MergeDimEmpresas
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.dimEmpresas);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH StgDeduplicado AS (
        SELECT s.*,
               ROW_NUMBER() OVER (PARTITION BY RTRIM(s.SVSGVL) ORDER BY s.SVDATE DESC, s.SVTIME DESC) AS rn
        FROM stg.dimEmpresas s
        WHERE RTRIM(ISNULL(s.SVSGVL, '')) <> ''
    ),
    Moneda AS (
        SELECT RIGHT('00' + CAST(m.CMPNY AS VARCHAR(10)), 2) AS SVSGVL, m.CCURCY
        FROM stg.dimEmpresaMoneda m
    ),
    StgNormalizado AS (
        SELECT
            RTRIM(s.SVSGVL)                                           AS SVSGVL,
            NULLIF(RTRIM(s.SVID), '')                                 AS SVID,
            NULLIF(RTRIM(s.SVLDES), '')                                AS SVLDES,
            TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(s.SVDATE AS BIGINT)))  AS SVDATE,
            TRY_CONVERT(TIME(0), STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(6), CAST(s.SVTIME AS BIGINT)), 6), 3, 0, ':'), 6, 0, ':')) AS SVTIME,
            NULLIF(RTRIM(mo.CCURCY), '')                               AS MonedaFuncional
        FROM StgDeduplicado s
        LEFT JOIN Moneda mo ON mo.SVSGVL = RTRIM(s.SVSGVL)
        WHERE s.rn = 1
    ),
    StgConHash AS (
        SELECT
            n.*,
            HASHBYTES('SHA2_256', (SELECT n.* FOR XML RAW, BINARY BASE64)) AS HashDiff
        FROM StgNormalizado n
    )
    MERGE [int].dimEmpresas AS destino
        USING StgConHash AS origen
        ON destino.SVSGVL = origen.SVSGVL
    WHEN MATCHED AND destino.HashDiff <> origen.HashDiff THEN
        UPDATE SET
            SVID             = origen.SVID,
            SVLDES           = origen.SVLDES,
            SVDATE           = origen.SVDATE,
            SVTIME           = origen.SVTIME,
            MonedaFuncional  = origen.MonedaFuncional,
            EsVigente        = 1,
            HashDiff         = origen.HashDiff,
            FechaCargaInt    = SYSDATETIME(),
            RunId            = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (SVSGVL, SVID, SVLDES, SVDATE, SVTIME, MonedaFuncional, HashDiff, RunId)
        VALUES (origen.SVSGVL, origen.SVID, origen.SVLDES, origen.SVDATE, origen.SVTIME, origen.MonedaFuncional, origen.HashDiff, @RunId)
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

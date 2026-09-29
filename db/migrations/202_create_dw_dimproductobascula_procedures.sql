-- 202: merge Silver -> Gold para dimProductoBascula. SCD Tipo 1 (sobrescribe).
-- Reutiliza el HashDiff ya calculado en [int].dimProductoBascula.

CREATE OR ALTER PROCEDURE dw.usp_MergeDimProductoBascula
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].dimProductoBascula);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH Origen AS (
        SELECT
            NUMPROD AS CodigoProductoBascula,
            MOMPROD AS DescripcionProductoBascula,
            EsVigente,
            HashDiff
        FROM [int].dimProductoBascula
    )
    MERGE dw.dimProductoBascula AS destino
        USING Origen AS origen
        ON destino.CodigoProductoBascula = origen.CodigoProductoBascula
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente) THEN
        UPDATE SET
            DescripcionProductoBascula   = origen.DescripcionProductoBascula,
            EsVigente                    = origen.EsVigente,
            HashDiff                     = origen.HashDiff,
            FechaCargaDw                 = SYSDATETIME(),
            RunId                        = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (CodigoProductoBascula, DescripcionProductoBascula, EsVigente, HashDiff, RunId)
        VALUES (origen.CodigoProductoBascula, origen.DescripcionProductoBascula, origen.EsVigente, origen.HashDiff, @RunId)
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

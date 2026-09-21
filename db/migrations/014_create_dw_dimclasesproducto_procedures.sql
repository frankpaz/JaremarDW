-- 014: merge Silver -> Gold para dimClasesProducto. SCD Tipo 1 (sobrescribe).
-- Reutiliza el HashDiff ya calculado en [int].dimClasesProducto.

CREATE OR ALTER PROCEDURE dw.usp_MergeDimClasesProducto
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].dimClasesProducto);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH Origen AS (
        SELECT
            ICLAS AS CodigoClase,
            ICDES AS DescripcionClase,
            EsVigente,
            HashDiff
        FROM [int].dimClasesProducto
    )
    MERGE dw.dimClasesProducto AS destino
        USING Origen AS origen
        ON destino.CodigoClase = origen.CodigoClase
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente) THEN
        UPDATE SET
            DescripcionClase = origen.DescripcionClase,
            EsVigente        = origen.EsVigente,
            HashDiff         = origen.HashDiff,
            FechaCargaDw     = SYSDATETIME(),
            RunId            = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (CodigoClase, DescripcionClase, EsVigente, HashDiff, RunId)
        VALUES (origen.CodigoClase, origen.DescripcionClase, origen.EsVigente, origen.HashDiff, @RunId)
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

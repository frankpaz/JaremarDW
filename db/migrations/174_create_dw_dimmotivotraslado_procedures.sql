-- 174: merge Silver -> Gold para dimMotivoTraslado. SCD Tipo 1 (sobrescribe).
-- Reutiliza el HashDiff ya calculado en [int].dimMotivoTraslado.

CREATE OR ALTER PROCEDURE dw.usp_MergeDimMotivoTraslado
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].dimMotivoTraslado);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH Origen AS (
        SELECT
            D901MT AS CodigoMotivoTraslado,
            D901DM AS DescripcionMotivoTraslado,
            EsVigente,
            HashDiff
        FROM [int].dimMotivoTraslado
    )
    MERGE dw.dimMotivoTraslado AS destino
        USING Origen AS origen
        ON destino.CodigoMotivoTraslado = origen.CodigoMotivoTraslado
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente) THEN
        UPDATE SET
            DescripcionMotivoTraslado = origen.DescripcionMotivoTraslado,
            EsVigente                 = origen.EsVigente,
            HashDiff                  = origen.HashDiff,
            FechaCargaDw              = SYSDATETIME(),
            RunId                     = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (CodigoMotivoTraslado, DescripcionMotivoTraslado, EsVigente, HashDiff, RunId)
        VALUES (origen.CodigoMotivoTraslado, origen.DescripcionMotivoTraslado, origen.EsVigente, origen.HashDiff, @RunId)
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

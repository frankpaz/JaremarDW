-- 198: merge Silver -> Gold para dimLugarBascula. SCD Tipo 1 (sobrescribe).
-- Reutiliza el HashDiff ya calculado en [int].dimLugarBascula.

CREATE OR ALTER PROCEDURE dw.usp_MergeDimLugarBascula
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].dimLugarBascula);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH Origen AS (
        SELECT
            NUMLUG AS CodigoLugar,
            MOMLUG AS DescripcionLugar,
            EsVigente,
            HashDiff
        FROM [int].dimLugarBascula
    )
    MERGE dw.dimLugarBascula AS destino
        USING Origen AS origen
        ON destino.CodigoLugar = origen.CodigoLugar
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente) THEN
        UPDATE SET
            DescripcionLugar   = origen.DescripcionLugar,
            EsVigente          = origen.EsVigente,
            HashDiff           = origen.HashDiff,
            FechaCargaDw       = SYSDATETIME(),
            RunId              = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (CodigoLugar, DescripcionLugar, EsVigente, HashDiff, RunId)
        VALUES (origen.CodigoLugar, origen.DescripcionLugar, origen.EsVigente, origen.HashDiff, @RunId)
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

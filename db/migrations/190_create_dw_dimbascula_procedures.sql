-- 190: merge Silver -> Gold para dimBascula. SCD Tipo 1 (sobrescribe).
-- Reutiliza el HashDiff ya calculado en [int].dimBascula.

CREATE OR ALTER PROCEDURE dw.usp_MergeDimBascula
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].dimBascula);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH Origen AS (
        SELECT
            NUMBAS AS CodigoBascula,
            MOMBAS AS NombreBascula,
            EsVigente,
            HashDiff
        FROM [int].dimBascula
    )
    MERGE dw.dimBascula AS destino
        USING Origen AS origen
        ON destino.CodigoBascula = origen.CodigoBascula
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente) THEN
        UPDATE SET
            NombreBascula   = origen.NombreBascula,
            EsVigente       = origen.EsVigente,
            HashDiff        = origen.HashDiff,
            FechaCargaDw    = SYSDATETIME(),
            RunId           = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (CodigoBascula, NombreBascula, EsVigente, HashDiff, RunId)
        VALUES (origen.CodigoBascula, origen.NombreBascula, origen.EsVigente, origen.HashDiff, @RunId)
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

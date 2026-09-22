-- 041: merge Silver -> Gold para dimSmaPlants. SCD Tipo 1 (sobrescribe).
-- Reutiliza el HashDiff ya calculado en [int].dimSmaPlants.

CREATE OR ALTER PROCEDURE dw.usp_MergeDimSmaPlants
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].dimSmaPlants);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH Origen AS (
        SELECT PlantId, PlantName, PlantTimezone, EsVigente, HashDiff
        FROM [int].dimSmaPlants
    )
    MERGE dw.dimSmaPlants AS destino
        USING Origen AS origen
        ON destino.PlantId = origen.PlantId
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente) THEN
        UPDATE SET
            PlantName      = origen.PlantName,
            PlantTimezone  = origen.PlantTimezone,
            EsVigente      = origen.EsVigente,
            HashDiff       = origen.HashDiff,
            FechaCargaDw   = SYSDATETIME(),
            RunId          = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (PlantId, PlantName, PlantTimezone, EsVigente, HashDiff, RunId)
        VALUES (origen.PlantId, origen.PlantName, origen.PlantTimezone, origen.EsVigente, origen.HashDiff, @RunId)
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

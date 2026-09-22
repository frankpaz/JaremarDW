-- 039: merge Bronze -> Silver para dimSmaPlants.

CREATE OR ALTER PROCEDURE [int].usp_MergeDimSmaPlants
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.dimSmaPlants);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH StgDeduplicado AS (
        SELECT s.*,
               ROW_NUMBER() OVER (PARTITION BY s.PlantId ORDER BY (SELECT NULL)) AS rn
        FROM stg.dimSmaPlants s
        WHERE s.PlantId IS NOT NULL
    ),
    StgNormalizado AS (
        SELECT
            s.PlantId,
            RTRIM(s.PlantName)      AS PlantName,
            RTRIM(s.PlantTimezone)  AS PlantTimezone
        FROM StgDeduplicado s
        WHERE s.rn = 1
    ),
    StgConHash AS (
        SELECT
            n.*,
            HASHBYTES('SHA2_256', (SELECT n.* FOR XML RAW, BINARY BASE64)) AS HashDiff
        FROM StgNormalizado n
    )
    MERGE [int].dimSmaPlants AS destino
        USING StgConHash AS origen
        ON destino.PlantId = origen.PlantId
    WHEN MATCHED AND destino.HashDiff <> origen.HashDiff THEN
        UPDATE SET
            PlantName      = origen.PlantName,
            PlantTimezone  = origen.PlantTimezone,
            EsVigente      = 1,
            HashDiff       = origen.HashDiff,
            FechaCargaInt  = SYSDATETIME(),
            RunId          = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (PlantId, PlantName, PlantTimezone, HashDiff, RunId)
        VALUES (origen.PlantId, origen.PlantName, origen.PlantTimezone, origen.HashDiff, @RunId)
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

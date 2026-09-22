-- 057: merge Silver -> Gold para dimSoliscloudStations. SCD Tipo 1 (sobrescribe).
-- Reutiliza el HashDiff ya calculado en [int].dimSoliscloudStations.

CREATE OR ALTER PROCEDURE dw.usp_MergeDimSoliscloudStations
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].dimSoliscloudStations);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH Origen AS (
        SELECT StationId, StationName, Addr, Country, TimeZone, CreateDate, EsVigente, HashDiff
        FROM [int].dimSoliscloudStations
    )
    MERGE dw.dimSoliscloudStations AS destino
        USING Origen AS origen
        ON destino.StationId = origen.StationId
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente) THEN
        UPDATE SET
            StationName   = origen.StationName,
            Addr          = origen.Addr,
            Country       = origen.Country,
            TimeZone      = origen.TimeZone,
            CreateDate    = origen.CreateDate,
            EsVigente     = origen.EsVigente,
            HashDiff      = origen.HashDiff,
            FechaCargaDw  = SYSDATETIME(),
            RunId         = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (StationId, StationName, Addr, Country, TimeZone, CreateDate, EsVigente, HashDiff, RunId)
        VALUES (origen.StationId, origen.StationName, origen.Addr, origen.Country, origen.TimeZone,
                origen.CreateDate, origen.EsVigente, origen.HashDiff, @RunId)
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

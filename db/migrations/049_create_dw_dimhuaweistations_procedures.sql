-- 049: merge Silver -> Gold para dimHuaweiStations. SCD Tipo 1 (sobrescribe).
-- Reutiliza el HashDiff ya calculado en [int].dimHuaweiStations.

CREATE OR ALTER PROCEDURE dw.usp_MergeDimHuaweiStations
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].dimHuaweiStations);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH Origen AS (
        SELECT
            StationCode, StationName, StationAddress, Longitude, Latitude, Capacity,
            ContactPerson, ContactMethod, GridConnectionDate, EsVigente, HashDiff
        FROM [int].dimHuaweiStations
    )
    MERGE dw.dimHuaweiStations AS destino
        USING Origen AS origen
        ON destino.StationCode = origen.StationCode
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente) THEN
        UPDATE SET
            StationName         = origen.StationName,
            StationAddress      = origen.StationAddress,
            Longitude           = origen.Longitude,
            Latitude            = origen.Latitude,
            Capacity            = origen.Capacity,
            ContactPerson       = origen.ContactPerson,
            ContactMethod       = origen.ContactMethod,
            GridConnectionDate  = origen.GridConnectionDate,
            EsVigente           = origen.EsVigente,
            HashDiff            = origen.HashDiff,
            FechaCargaDw        = SYSDATETIME(),
            RunId               = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (
            StationCode, StationName, StationAddress, Longitude, Latitude, Capacity,
            ContactPerson, ContactMethod, GridConnectionDate, EsVigente, HashDiff, RunId
        )
        VALUES (
            origen.StationCode, origen.StationName, origen.StationAddress, origen.Longitude, origen.Latitude,
            origen.Capacity, origen.ContactPerson, origen.ContactMethod, origen.GridConnectionDate,
            origen.EsVigente, origen.HashDiff, @RunId
        )
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

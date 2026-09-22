-- 047: merge Bronze -> Silver para dimHuaweiStations.

CREATE OR ALTER PROCEDURE [int].usp_MergeDimHuaweiStations
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.dimHuaweiStations);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH StgDeduplicado AS (
        SELECT s.*,
               ROW_NUMBER() OVER (PARTITION BY RTRIM(s.StationCode) ORDER BY (SELECT NULL)) AS rn
        FROM stg.dimHuaweiStations s
        WHERE RTRIM(ISNULL(s.StationCode, '')) <> ''
    ),
    StgNormalizado AS (
        SELECT
            RTRIM(s.StationCode)                       AS StationCode,
            NULLIF(RTRIM(s.StationName), '')            AS StationName,
            NULLIF(RTRIM(s.StationAddress), '')         AS StationAddress,
            s.Longitude,
            s.Latitude,
            s.Capacity,
            NULLIF(RTRIM(s.ContactPerson), '')          AS ContactPerson,
            NULLIF(RTRIM(s.ContactMethod), '')          AS ContactMethod,
            TRY_CONVERT(DATETIMEOFFSET(7), s.GridConnectionDate) AS GridConnectionDate
        FROM StgDeduplicado s
        WHERE s.rn = 1
    ),
    StgConHash AS (
        SELECT
            n.*,
            HASHBYTES('SHA2_256', (SELECT n.* FOR XML RAW, BINARY BASE64)) AS HashDiff
        FROM StgNormalizado n
    )
    MERGE [int].dimHuaweiStations AS destino
        USING StgConHash AS origen
        ON destino.StationCode = origen.StationCode
    WHEN MATCHED AND destino.HashDiff <> origen.HashDiff THEN
        UPDATE SET
            StationName         = origen.StationName,
            StationAddress      = origen.StationAddress,
            Longitude           = origen.Longitude,
            Latitude            = origen.Latitude,
            Capacity            = origen.Capacity,
            ContactPerson       = origen.ContactPerson,
            ContactMethod       = origen.ContactMethod,
            GridConnectionDate  = origen.GridConnectionDate,
            EsVigente           = 1,
            HashDiff            = origen.HashDiff,
            FechaCargaInt       = SYSDATETIME(),
            RunId               = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (
            StationCode, StationName, StationAddress, Longitude, Latitude, Capacity,
            ContactPerson, ContactMethod, GridConnectionDate, HashDiff, RunId
        )
        VALUES (
            origen.StationCode, origen.StationName, origen.StationAddress, origen.Longitude, origen.Latitude,
            origen.Capacity, origen.ContactPerson, origen.ContactMethod, origen.GridConnectionDate, origen.HashDiff, @RunId
        )
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

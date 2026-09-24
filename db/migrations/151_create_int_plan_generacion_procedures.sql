-- 151: merge Bronze -> Silver del plan de generacion de energia.
-- Historial de versiones: la version cargada en esta corrida pasa a ser la
-- vigente de cada (Fecha, CodigoInversor) que trae el stg; las demas versiones
-- de ESA fecha e inversor quedan EsVigente = 0 (no se borran). Una carga que
-- cubre menos fechas que la anterior no deja huecos: las fechas que no trae
-- conservan su version vigente.

CREATE OR ALTER PROCEDURE [int].usp_MergeDimPlanGeneracion
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.dimPlanGeneracion);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH StgDeduplicado AS (
        SELECT s.*,
               ROW_NUMBER() OVER (PARTITION BY s.Fecha, RTRIM(s.CodigoInversor), RTRIM(s.PlanVersion) ORDER BY s.FechaCargaStg DESC) AS rn
        FROM stg.dimPlanGeneracion s
        WHERE RTRIM(ISNULL(s.CodigoInversor, '')) <> '' AND RTRIM(ISNULL(s.PlanVersion, '')) <> ''
    ),
    StgNormalizado AS (
        SELECT
            s.Fecha,
            RTRIM(s.CodigoInversor)  AS CodigoInversor,
            RTRIM(s.PlanVersion)     AS PlanVersion,
            NULLIF(RTRIM(s.SerialInversor), '') AS SerialInversor,
            s.PlanKwh,
            RTRIM(s.PlanFuente)      AS PlanFuente,
            s.ArchivoOrigen
        FROM StgDeduplicado s
        WHERE s.rn = 1
    ),
    StgConHash AS (
        SELECT
            n.*,
            HASHBYTES('SHA2_256', (SELECT n.PlanKwh, n.PlanFuente, n.SerialInversor FOR XML RAW, BINARY BASE64)) AS HashDiff
        FROM StgNormalizado n
    )
    MERGE [int].dimPlanGeneracion AS destino
        USING StgConHash AS origen
        ON destino.Fecha = origen.Fecha AND destino.CodigoInversor = origen.CodigoInversor
           AND destino.PlanVersion = origen.PlanVersion
    WHEN MATCHED AND destino.HashDiff <> origen.HashDiff THEN
        UPDATE SET
            SerialInversor = origen.SerialInversor,
            PlanKwh        = origen.PlanKwh,
            PlanFuente     = origen.PlanFuente,
            ArchivoOrigen  = origen.ArchivoOrigen,
            HashDiff       = origen.HashDiff,
            FechaCargaInt  = SYSDATETIME(),
            RunId          = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (Fecha, CodigoInversor, PlanVersion, SerialInversor, PlanKwh, PlanFuente, ArchivoOrigen, HashDiff, RunId)
        VALUES (origen.Fecha, origen.CodigoInversor, origen.PlanVersion, origen.SerialInversor, origen.PlanKwh, origen.PlanFuente,
                origen.ArchivoOrigen, origen.HashDiff, @RunId)
    OUTPUT $action INTO #AccionesMerge;

    ;WITH Cargadas AS (
        SELECT DISTINCT Fecha, RTRIM(CodigoInversor) AS CodigoInversor, RTRIM(PlanVersion) AS PlanVersion
        FROM stg.dimPlanGeneracion
    )
    UPDATE i
    SET EsVigente     = CASE WHEN c_ver.PlanVersion IS NOT NULL THEN 1 ELSE 0 END,
        FechaCargaInt = SYSDATETIME(),
        RunId         = @RunId
    FROM [int].dimPlanGeneracion i
    JOIN (SELECT DISTINCT Fecha, CodigoInversor FROM Cargadas) c
         ON c.Fecha = i.Fecha AND c.CodigoInversor = i.CodigoInversor
    LEFT JOIN Cargadas c_ver
         ON c_ver.Fecha = i.Fecha AND c_ver.CodigoInversor = i.CodigoInversor AND c_ver.PlanVersion = i.PlanVersion
    WHERE i.EsVigente <> CASE WHEN c_ver.PlanVersion IS NOT NULL THEN 1 ELSE 0 END;

    SELECT
        @FilasLeidas                                                                 AS FilasLeidas,
        ISNULL(SUM(CASE WHEN Accion = 'INSERT' THEN 1 ELSE 0 END), 0)                AS FilasInsertadas,
        ISNULL(SUM(CASE WHEN Accion = 'UPDATE' THEN 1 ELSE 0 END), 0)                AS FilasActualizadas,
        @FilasLeidas - ISNULL(SUM(CASE WHEN Accion = 'INSERT' THEN 1 ELSE 0 END), 0)
                      - ISNULL(SUM(CASE WHEN Accion = 'UPDATE' THEN 1 ELSE 0 END), 0) AS FilasIgnoradas
    FROM #AccionesMerge;
END
GO

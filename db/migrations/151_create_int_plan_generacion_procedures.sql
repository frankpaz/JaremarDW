-- 151: merge Bronze -> Silver del plan de generacion de energia.

CREATE OR ALTER PROCEDURE [int].usp_MergeDimPlantaSolar
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.dimPlantaSolar);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH StgDeduplicado AS (
        SELECT s.*,
               ROW_NUMBER() OVER (PARTITION BY RTRIM(s.CodigoPI) ORDER BY s.FechaCargaStg DESC) AS rn
        FROM stg.dimPlantaSolar s
        WHERE RTRIM(ISNULL(s.CodigoPI, '')) <> ''
    ),
    StgNormalizado AS (
        SELECT
            RTRIM(s.CodigoPI)      AS CodigoPI,
            RTRIM(s.Plantel)       AS Plantel,
            RTRIM(s.CodigoSitio)   AS CodigoSitio,
            s.CapacidadDcKwp,
            s.CapacidadAcKw,
            s.ArchivoOrigen
        FROM StgDeduplicado s
        WHERE s.rn = 1
    ),
    StgConHash AS (
        SELECT
            n.*,
            HASHBYTES('SHA2_256', (SELECT n.Plantel, n.CodigoSitio, n.CapacidadDcKwp, n.CapacidadAcKw FOR XML RAW, BINARY BASE64)) AS HashDiff
        FROM StgNormalizado n
    )
    MERGE [int].dimPlantaSolar AS destino
        USING StgConHash AS origen
        ON destino.CodigoPI = origen.CodigoPI
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente = 0) THEN
        UPDATE SET
            Plantel         = origen.Plantel,
            CodigoSitio     = origen.CodigoSitio,
            CapacidadDcKwp  = origen.CapacidadDcKwp,
            CapacidadAcKw   = origen.CapacidadAcKw,
            ArchivoOrigen   = origen.ArchivoOrigen,
            EsVigente       = 1,
            HashDiff        = origen.HashDiff,
            FechaCargaInt   = SYSDATETIME(),
            RunId           = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (CodigoPI, Plantel, CodigoSitio, CapacidadDcKwp, CapacidadAcKw, ArchivoOrigen, HashDiff, RunId)
        VALUES (origen.CodigoPI, origen.Plantel, origen.CodigoSitio, origen.CapacidadDcKwp, origen.CapacidadAcKw,
                origen.ArchivoOrigen, origen.HashDiff, @RunId)
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

-- Plan mensual: historial de versiones. La version cargada en esta corrida
-- pasa a ser la vigente de cada (Anio, Plantel) que trae el stg; las demas
-- versiones de ese (Anio, Plantel) quedan EsVigente = 0 (no se borran).
CREATE OR ALTER PROCEDURE [int].usp_MergeDimPlanGeneracionMensual
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.dimPlanGeneracionMensual);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH StgDeduplicado AS (
        SELECT s.*,
               ROW_NUMBER() OVER (PARTITION BY s.Anio, s.Mes, RTRIM(s.Plantel), RTRIM(s.PlanVersion) ORDER BY s.FechaCargaStg DESC) AS rn
        FROM stg.dimPlanGeneracionMensual s
        WHERE RTRIM(ISNULL(s.Plantel, '')) <> '' AND RTRIM(ISNULL(s.PlanVersion, '')) <> ''
    ),
    StgNormalizado AS (
        SELECT
            s.Anio,
            s.Mes,
            RTRIM(s.Plantel)       AS Plantel,
            RTRIM(s.PlanVersion)   AS PlanVersion,
            s.PlanKwh,
            RTRIM(s.PlanFuente)    AS PlanFuente,
            s.ArchivoOrigen
        FROM StgDeduplicado s
        WHERE s.rn = 1
    ),
    StgConHash AS (
        SELECT
            n.*,
            HASHBYTES('SHA2_256', (SELECT n.PlanKwh, n.PlanFuente FOR XML RAW, BINARY BASE64)) AS HashDiff
        FROM StgNormalizado n
    )
    MERGE [int].dimPlanGeneracionMensual AS destino
        USING StgConHash AS origen
        ON destino.Anio = origen.Anio AND destino.Mes = origen.Mes
           AND destino.Plantel = origen.Plantel AND destino.PlanVersion = origen.PlanVersion
    WHEN MATCHED AND destino.HashDiff <> origen.HashDiff THEN
        UPDATE SET
            PlanKwh        = origen.PlanKwh,
            PlanFuente     = origen.PlanFuente,
            ArchivoOrigen  = origen.ArchivoOrigen,
            HashDiff       = origen.HashDiff,
            FechaCargaInt  = SYSDATETIME(),
            RunId          = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (Anio, Mes, Plantel, PlanVersion, PlanKwh, PlanFuente, ArchivoOrigen, HashDiff, RunId)
        VALUES (origen.Anio, origen.Mes, origen.Plantel, origen.PlanVersion, origen.PlanKwh, origen.PlanFuente,
                origen.ArchivoOrigen, origen.HashDiff, @RunId)
    OUTPUT $action INTO #AccionesMerge;

    ;WITH Cargadas AS (
        SELECT DISTINCT Anio, RTRIM(Plantel) AS Plantel, RTRIM(PlanVersion) AS PlanVersion
        FROM stg.dimPlanGeneracionMensual
    )
    UPDATE i
    SET EsVigente     = CASE WHEN c_ver.PlanVersion IS NOT NULL THEN 1 ELSE 0 END,
        FechaCargaInt = SYSDATETIME(),
        RunId         = @RunId
    FROM [int].dimPlanGeneracionMensual i
    JOIN (SELECT DISTINCT Anio, Plantel FROM Cargadas) c ON c.Anio = i.Anio AND c.Plantel = i.Plantel
    LEFT JOIN Cargadas c_ver ON c_ver.Anio = i.Anio AND c_ver.Plantel = i.Plantel AND c_ver.PlanVersion = i.PlanVersion
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

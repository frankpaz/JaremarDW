-- 153: merge Silver -> Gold del plan de generacion de energia. SCD Tipo 1
-- (sobrescribe); reutiliza el HashDiff de [int]. El historial de versiones del
-- plan se conserva: solo cambia EsVigente.

CREATE OR ALTER PROCEDURE dw.usp_MergeDimPlantaSolar
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].dimPlantaSolar);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH Origen AS (
        SELECT CodigoPI, Plantel, CodigoSitio, CapacidadDcKwp, CapacidadAcKw, EsVigente, HashDiff
        FROM [int].dimPlantaSolar
    )
    MERGE dw.dimPlantaSolar AS destino
        USING Origen AS origen
        ON destino.CodigoPI = origen.CodigoPI
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente) THEN
        UPDATE SET
            Plantel         = origen.Plantel,
            CodigoSitio     = origen.CodigoSitio,
            CapacidadDcKwp  = origen.CapacidadDcKwp,
            CapacidadAcKw   = origen.CapacidadAcKw,
            EsVigente       = origen.EsVigente,
            HashDiff        = origen.HashDiff,
            FechaCargaDw    = SYSDATETIME(),
            RunId           = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (CodigoPI, Plantel, CodigoSitio, CapacidadDcKwp, CapacidadAcKw, EsVigente, HashDiff, RunId)
        VALUES (origen.CodigoPI, origen.Plantel, origen.CodigoSitio, origen.CapacidadDcKwp, origen.CapacidadAcKw,
                origen.EsVigente, origen.HashDiff, @RunId)
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

CREATE OR ALTER PROCEDURE dw.usp_MergeDimPlanGeneracionMensual
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].dimPlanGeneracionMensual);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH Origen AS (
        SELECT Anio, Mes, Plantel, PlanVersion, PlanKwh, PlanFuente, ArchivoOrigen, EsVigente, HashDiff
        FROM [int].dimPlanGeneracionMensual
    )
    MERGE dw.dimPlanGeneracionMensual AS destino
        USING Origen AS origen
        ON destino.Anio = origen.Anio AND destino.Mes = origen.Mes
           AND destino.Plantel = origen.Plantel AND destino.PlanVersion = origen.PlanVersion
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente) THEN
        UPDATE SET
            PlanKwh        = origen.PlanKwh,
            PlanFuente     = origen.PlanFuente,
            ArchivoOrigen  = origen.ArchivoOrigen,
            EsVigente      = origen.EsVigente,
            HashDiff       = origen.HashDiff,
            FechaCargaDw   = SYSDATETIME(),
            RunId          = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (Anio, Mes, Plantel, PlanVersion, PlanKwh, PlanFuente, ArchivoOrigen, EsVigente, HashDiff, RunId)
        VALUES (origen.Anio, origen.Mes, origen.Plantel, origen.PlanVersion, origen.PlanKwh, origen.PlanFuente,
                origen.ArchivoOrigen, origen.EsVigente, origen.HashDiff, @RunId)
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

-- 160: merge Bronze -> Silver -> Gold de dimPlanGeneracion con la estructura de la 159
-- (solo campos del Excel + auditoria).
--
-- Versiones: la version cargada en esta corrida pasa a ser la vigente de cada (Fecha,
-- inversor) que trae el stg; las demas versiones de ESA fecha e inversor quedan EsVigente = 0.
-- El inversor se identifica por el DISPOSITIVO (Proveedor + Inversor), no por su nombre
-- (InversorId): el mismo equipo puede llamarse 'JABON-2' en un archivo y 'SN 3006256658' en otro.

CREATE OR ALTER PROCEDURE [int].usp_MergeDimPlanGeneracion
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.dimPlanGeneracion);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH StgDeduplicado AS (
        SELECT s.*,
               ROW_NUMBER() OVER (PARTITION BY s.Fecha, RTRIM(s.InversorId), RTRIM(s.PlanVersion) ORDER BY s.FechaCargaStg DESC) AS rn
        FROM stg.dimPlanGeneracion s
    ),
    StgNormalizado AS (
        SELECT
            s.Fecha,
            RTRIM(s.Planta)              AS Planta,
            RTRIM(s.Proveedor)           AS Proveedor,
            RTRIM(s.Inversor)            AS Inversor,
            RTRIM(s.InversorId)          AS InversorId,
            s.Mes,
            RTRIM(s.NombreMes)           AS NombreMes,
            RTRIM(s.Ubicacion)           AS Ubicacion,
            s.PlanDiarioAsignado,
            s.PlanDiarioInversor,
            RTRIM(s.PlanFuente)          AS PlanFuente,
            RTRIM(s.PlanVersion)         AS PlanVersion,
            s.ArchivoOrigen
        FROM StgDeduplicado s
        WHERE s.rn = 1
    ),
    StgConHash AS (
        SELECT
            n.*,
            HASHBYTES('SHA2_256', (SELECT n.Planta, n.Proveedor, n.Inversor, n.Mes, n.NombreMes, n.Ubicacion,
                                          n.PlanDiarioAsignado, n.PlanDiarioInversor, n.PlanFuente FOR XML RAW, BINARY BASE64)) AS HashDiff
        FROM StgNormalizado n
    )
    MERGE [int].dimPlanGeneracion AS destino
        USING StgConHash AS origen
        ON destino.Fecha = origen.Fecha AND destino.InversorId = origen.InversorId
           AND destino.PlanVersion = origen.PlanVersion
    WHEN MATCHED AND destino.HashDiff <> origen.HashDiff THEN
        UPDATE SET
            Planta              = origen.Planta,
            Proveedor           = origen.Proveedor,
            Inversor            = origen.Inversor,
            Mes                 = origen.Mes,
            NombreMes           = origen.NombreMes,
            Ubicacion           = origen.Ubicacion,
            PlanDiarioAsignado  = origen.PlanDiarioAsignado,
            PlanDiarioInversor  = origen.PlanDiarioInversor,
            PlanFuente          = origen.PlanFuente,
            ArchivoOrigen       = origen.ArchivoOrigen,
            HashDiff            = origen.HashDiff,
            FechaCargaInt       = SYSDATETIME(),
            RunId               = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (Fecha, Planta, Proveedor, Inversor, InversorId, Mes, NombreMes, Ubicacion, PlanDiarioAsignado,
                PlanDiarioInversor, PlanFuente, PlanVersion, ArchivoOrigen, HashDiff, RunId)
        VALUES (origen.Fecha, origen.Planta, origen.Proveedor, origen.Inversor, origen.InversorId, origen.Mes,
                origen.NombreMes, origen.Ubicacion, origen.PlanDiarioAsignado, origen.PlanDiarioInversor,
                origen.PlanFuente, origen.PlanVersion, origen.ArchivoOrigen, origen.HashDiff, @RunId)
    OUTPUT $action INTO #AccionesMerge;

    ;WITH Cargadas AS (
        SELECT DISTINCT Fecha, RTRIM(PlanVersion) AS PlanVersion, RTRIM(Proveedor) + ':' + RTRIM(Inversor) AS Grupo
        FROM stg.dimPlanGeneracion
    ),
    Afectadas AS (SELECT DISTINCT Fecha, Grupo FROM Cargadas)
    UPDATE i
    SET EsVigente     = CASE WHEN c_ver.PlanVersion IS NOT NULL THEN 1 ELSE 0 END,
        FechaCargaInt = SYSDATETIME(),
        RunId         = @RunId
    FROM [int].dimPlanGeneracion i
    CROSS APPLY (SELECT i.Proveedor + ':' + i.Inversor AS Grupo) g
    JOIN Afectadas a ON a.Fecha = i.Fecha AND a.Grupo = g.Grupo
    LEFT JOIN Cargadas c_ver ON c_ver.Fecha = i.Fecha AND c_ver.Grupo = g.Grupo AND c_ver.PlanVersion = i.PlanVersion
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

CREATE OR ALTER PROCEDURE dw.usp_MergeDimPlanGeneracion
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].dimPlanGeneracion);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH Origen AS (
        SELECT Fecha, Planta, Proveedor, Inversor, InversorId, Mes, NombreMes, Ubicacion, PlanDiarioAsignado,
               PlanDiarioInversor, PlanFuente, PlanVersion, ArchivoOrigen, EsVigente, HashDiff
        FROM [int].dimPlanGeneracion
    )
    MERGE dw.dimPlanGeneracion AS destino
        USING Origen AS origen
        ON destino.Fecha = origen.Fecha AND destino.InversorId = origen.InversorId
           AND destino.PlanVersion = origen.PlanVersion
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente) THEN
        UPDATE SET
            Planta              = origen.Planta,
            Proveedor           = origen.Proveedor,
            Inversor            = origen.Inversor,
            Mes                 = origen.Mes,
            NombreMes           = origen.NombreMes,
            Ubicacion           = origen.Ubicacion,
            PlanDiarioAsignado  = origen.PlanDiarioAsignado,
            PlanDiarioInversor  = origen.PlanDiarioInversor,
            PlanFuente          = origen.PlanFuente,
            ArchivoOrigen       = origen.ArchivoOrigen,
            EsVigente           = origen.EsVigente,
            HashDiff            = origen.HashDiff,
            FechaCargaDw        = SYSDATETIME(),
            RunId               = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (Fecha, Planta, Proveedor, Inversor, InversorId, Mes, NombreMes, Ubicacion, PlanDiarioAsignado,
                PlanDiarioInversor, PlanFuente, PlanVersion, ArchivoOrigen, EsVigente, HashDiff, RunId)
        VALUES (origen.Fecha, origen.Planta, origen.Proveedor, origen.Inversor, origen.InversorId, origen.Mes,
                origen.NombreMes, origen.Ubicacion, origen.PlanDiarioAsignado, origen.PlanDiarioInversor,
                origen.PlanFuente, origen.PlanVersion, origen.ArchivoOrigen, origen.EsVigente, origen.HashDiff, @RunId)
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

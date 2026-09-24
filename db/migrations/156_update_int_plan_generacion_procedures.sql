-- 156: merge Bronze -> Silver del plan de generacion, con las columnas nuevas de la
-- migracion 155 (Planta, Proveedor, DispositivoId, Ubicacion, Mes, NombreMes,
-- PlanDiarioAsignado). Misma logica de versiones que la 151: la version cargada en
-- esta corrida pasa a ser la vigente de cada (Fecha, CodigoInversor) que trae el stg;
-- las demas versiones de ESA fecha e inversor quedan EsVigente = 0.
-- Un 'inversor' se identifica por el DISPOSITIVO (Proveedor + DispositivoId) cuando lo
-- trae, no por su nombre: el mismo equipo puede llamarse 'JABON-2' en un archivo y
-- 'SN 3006256658' en otro (nombre del portal), y no debe quedar vigente dos veces. Sin
-- DispositivoId (versiones anteriores) se usa CodigoInversor.

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
            RTRIM(s.CodigoInversor)                    AS CodigoInversor,
            RTRIM(s.PlanVersion)                       AS PlanVersion,
            NULLIF(RTRIM(s.SerialInversor), '')        AS SerialInversor,
            NULLIF(RTRIM(s.Planta), '')                AS Planta,
            NULLIF(RTRIM(s.Proveedor), '')             AS Proveedor,
            NULLIF(RTRIM(s.DispositivoId), '')         AS DispositivoId,
            NULLIF(RTRIM(s.Ubicacion), '')             AS Ubicacion,
            s.Mes,
            NULLIF(RTRIM(s.NombreMes), '')             AS NombreMes,
            s.PlanDiarioAsignado,
            s.PlanKwh,
            RTRIM(s.PlanFuente)                        AS PlanFuente,
            s.ArchivoOrigen
        FROM StgDeduplicado s
        WHERE s.rn = 1
    ),
    StgConHash AS (
        SELECT
            n.*,
            HASHBYTES('SHA2_256', (SELECT n.PlanKwh, n.PlanFuente, n.SerialInversor, n.Planta, n.Proveedor, n.DispositivoId,
                                          n.Ubicacion, n.Mes, n.NombreMes, n.PlanDiarioAsignado FOR XML RAW, BINARY BASE64)) AS HashDiff
        FROM StgNormalizado n
    )
    MERGE [int].dimPlanGeneracion AS destino
        USING StgConHash AS origen
        ON destino.Fecha = origen.Fecha AND destino.CodigoInversor = origen.CodigoInversor
           AND destino.PlanVersion = origen.PlanVersion
    WHEN MATCHED AND destino.HashDiff <> origen.HashDiff THEN
        UPDATE SET
            SerialInversor      = origen.SerialInversor,
            Planta              = origen.Planta,
            Proveedor           = origen.Proveedor,
            DispositivoId       = origen.DispositivoId,
            Ubicacion           = origen.Ubicacion,
            Mes                 = origen.Mes,
            NombreMes           = origen.NombreMes,
            PlanDiarioAsignado  = origen.PlanDiarioAsignado,
            PlanKwh             = origen.PlanKwh,
            PlanFuente          = origen.PlanFuente,
            ArchivoOrigen       = origen.ArchivoOrigen,
            HashDiff            = origen.HashDiff,
            FechaCargaInt       = SYSDATETIME(),
            RunId               = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (Fecha, CodigoInversor, PlanVersion, SerialInversor, Planta, Proveedor, DispositivoId, Ubicacion, Mes,
                NombreMes, PlanDiarioAsignado, PlanKwh, PlanFuente, ArchivoOrigen, HashDiff, RunId)
        VALUES (origen.Fecha, origen.CodigoInversor, origen.PlanVersion, origen.SerialInversor, origen.Planta,
                origen.Proveedor, origen.DispositivoId, origen.Ubicacion, origen.Mes, origen.NombreMes,
                origen.PlanDiarioAsignado, origen.PlanKwh, origen.PlanFuente, origen.ArchivoOrigen, origen.HashDiff, @RunId)
    OUTPUT $action INTO #AccionesMerge;

    ;WITH Cargadas AS (
        SELECT DISTINCT
               Fecha,
               RTRIM(PlanVersion) AS PlanVersion,
               CASE WHEN NULLIF(RTRIM(DispositivoId), '') IS NOT NULL
                    THEN ISNULL(RTRIM(Proveedor), '') + ':' + RTRIM(DispositivoId)
                    ELSE RTRIM(CodigoInversor) END AS Grupo
        FROM stg.dimPlanGeneracion
    ),
    Afectadas AS (SELECT DISTINCT Fecha, Grupo FROM Cargadas)
    UPDATE i
    SET EsVigente     = CASE WHEN c_ver.PlanVersion IS NOT NULL THEN 1 ELSE 0 END,
        FechaCargaInt = SYSDATETIME(),
        RunId         = @RunId
    FROM [int].dimPlanGeneracion i
    CROSS APPLY (SELECT CASE WHEN i.DispositivoId IS NOT NULL
                             THEN ISNULL(i.Proveedor, '') + ':' + i.DispositivoId
                             ELSE i.CodigoInversor END AS Grupo) g
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

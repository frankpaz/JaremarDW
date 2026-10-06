-- 259: merges del catalogo de plantas (ver 258) y de dimHuaweiDevices, que ahora guarda la capacidad
-- que informa el portal (InstalledCapacityKwp). Los merge de Huawei son los de la 257 mas esa columna.

-- Silver: stg.dimPlantaSolar -> [int].dimPlantaSolar (FULL: lo que no viene queda con EsVigente = 0).
CREATE OR ALTER PROCEDURE [int].usp_MergeDimPlantaSolar
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.dimPlantaSolar);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH StgDeduplicado AS (
        SELECT s.*,
               ROW_NUMBER() OVER (PARTITION BY RTRIM(s.Planta) ORDER BY (SELECT NULL)) AS rn
        FROM stg.dimPlantaSolar s
        WHERE RTRIM(ISNULL(s.Planta, '')) <> ''
    ),
    StgNormalizado AS (
        SELECT
            RTRIM(s.Planta)                     AS Planta,
            NULLIF(RTRIM(s.Plantel), '')        AS Plantel,
            s.Orden,
            NULLIF(RTRIM(s.MeteoSite), '')      AS MeteoSite,
            ISNULL(s.EnReporte, 0)              AS EnReporte,
            NULLIF(RTRIM(s.ArchivoOrigen), '')  AS ArchivoOrigen
        FROM StgDeduplicado s
        WHERE s.rn = 1
    ),
    StgConHash AS (
        SELECT n.*,
               HASHBYTES('SHA2_256', (SELECT n.Planta, n.Plantel, n.Orden, n.MeteoSite, n.EnReporte FOR XML RAW, BINARY BASE64)) AS HashDiff
        FROM StgNormalizado n
    )
    MERGE [int].dimPlantaSolar AS destino
        USING StgConHash AS origen
        ON destino.Planta = origen.Planta
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente = 0) THEN
        UPDATE SET
            Plantel       = origen.Plantel,
            Orden         = origen.Orden,
            MeteoSite     = origen.MeteoSite,
            EnReporte     = origen.EnReporte,
            ArchivoOrigen = origen.ArchivoOrigen,
            EsVigente     = 1,
            HashDiff      = origen.HashDiff,
            FechaCargaInt = SYSDATETIME(),
            RunId         = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (Planta, Plantel, Orden, MeteoSite, EnReporte, ArchivoOrigen, HashDiff, RunId)
        VALUES (origen.Planta, origen.Plantel, origen.Orden, origen.MeteoSite, origen.EnReporte, origen.ArchivoOrigen,
                origen.HashDiff, @RunId)
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

-- Silver: stg.dimPlantaSolarOrigen -> [int].dimPlantaSolarOrigen (FULL). Planta NULL = agrupador excluido.
CREATE OR ALTER PROCEDURE [int].usp_MergeDimPlantaSolarOrigen
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.dimPlantaSolarOrigen);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH StgDeduplicado AS (
        SELECT s.*,
               ROW_NUMBER() OVER (PARTITION BY LOWER(RTRIM(s.Proveedor)), RTRIM(s.CodigoOrigen) ORDER BY (SELECT NULL)) AS rn
        FROM stg.dimPlantaSolarOrigen s
        WHERE RTRIM(ISNULL(s.Proveedor, '')) <> '' AND RTRIM(ISNULL(s.CodigoOrigen, '')) <> ''
    ),
    StgNormalizado AS (
        SELECT
            LOWER(RTRIM(s.Proveedor))           AS Proveedor,
            RTRIM(s.CodigoOrigen)               AS CodigoOrigen,
            NULLIF(RTRIM(s.NombreOrigen), '')   AS NombreOrigen,
            NULLIF(RTRIM(s.Planta), '')         AS Planta,
            NULLIF(RTRIM(s.ArchivoOrigen), '')  AS ArchivoOrigen
        FROM StgDeduplicado s
        WHERE s.rn = 1
    ),
    StgConHash AS (
        SELECT n.*,
               HASHBYTES('SHA2_256', (SELECT n.Proveedor, n.CodigoOrigen, n.NombreOrigen, n.Planta FOR XML RAW, BINARY BASE64)) AS HashDiff
        FROM StgNormalizado n
    )
    MERGE [int].dimPlantaSolarOrigen AS destino
        USING StgConHash AS origen
        ON destino.Proveedor = origen.Proveedor AND destino.CodigoOrigen = origen.CodigoOrigen
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente = 0) THEN
        UPDATE SET
            NombreOrigen  = origen.NombreOrigen,
            Planta        = origen.Planta,
            ArchivoOrigen = origen.ArchivoOrigen,
            EsVigente     = 1,
            HashDiff      = origen.HashDiff,
            FechaCargaInt = SYSDATETIME(),
            RunId         = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (Proveedor, CodigoOrigen, NombreOrigen, Planta, ArchivoOrigen, HashDiff, RunId)
        VALUES (origen.Proveedor, origen.CodigoOrigen, origen.NombreOrigen, origen.Planta, origen.ArchivoOrigen,
                origen.HashDiff, @RunId)
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

-- Gold: [int].dimPlantaSolar -> dw.dimPlantaSolar (SCD Tipo 1, llave PlantaSolarKey estable).
CREATE OR ALTER PROCEDURE dw.usp_MergeDimPlantaSolar
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].dimPlantaSolar);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    MERGE dw.dimPlantaSolar AS destino
        USING [int].dimPlantaSolar AS origen
        ON destino.Planta = origen.Planta
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente) THEN
        UPDATE SET
            Plantel       = origen.Plantel,
            Orden         = origen.Orden,
            MeteoSite     = origen.MeteoSite,
            EnReporte     = origen.EnReporte,
            ArchivoOrigen = origen.ArchivoOrigen,
            EsVigente     = origen.EsVigente,
            HashDiff      = origen.HashDiff,
            FechaCargaDw  = SYSDATETIME(),
            RunId         = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (Planta, Plantel, Orden, MeteoSite, EnReporte, ArchivoOrigen, EsVigente, HashDiff, RunId)
        VALUES (origen.Planta, origen.Plantel, origen.Orden, origen.MeteoSite, origen.EnReporte, origen.ArchivoOrigen,
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

-- Gold: [int].dimPlantaSolarOrigen -> dw.dimPlantaSolarOrigen. Resuelve PlantaSolarKey (cargar antes
-- dw.dimPlantaSolar); la llave se refresca aunque el HashDiff no cambie.
CREATE OR ALTER PROCEDURE dw.usp_MergeDimPlantaSolarOrigen
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT o.Proveedor, o.CodigoOrigen, o.NombreOrigen, o.Planta, p.PlantaSolarKey, o.ArchivoOrigen, o.EsVigente, o.HashDiff
    INTO #Origen
    FROM [int].dimPlantaSolarOrigen o
    LEFT JOIN dw.dimPlantaSolar p ON p.Planta = o.Planta;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM #Origen);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    MERGE dw.dimPlantaSolarOrigen AS destino
        USING #Origen AS origen
        ON destino.Proveedor = origen.Proveedor AND destino.CodigoOrigen = origen.CodigoOrigen
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente
                      OR ISNULL(destino.PlantaSolarKey, -1) <> ISNULL(origen.PlantaSolarKey, -1)) THEN
        UPDATE SET
            NombreOrigen   = origen.NombreOrigen,
            Planta         = origen.Planta,
            PlantaSolarKey = origen.PlantaSolarKey,
            ArchivoOrigen  = origen.ArchivoOrigen,
            EsVigente      = origen.EsVigente,
            HashDiff       = origen.HashDiff,
            FechaCargaDw   = SYSDATETIME(),
            RunId          = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (Proveedor, CodigoOrigen, NombreOrigen, Planta, PlantaSolarKey, ArchivoOrigen, EsVigente, HashDiff, RunId)
        VALUES (origen.Proveedor, origen.CodigoOrigen, origen.NombreOrigen, origen.Planta, origen.PlantaSolarKey,
                origen.ArchivoOrigen, origen.EsVigente, origen.HashDiff, @RunId)
    OUTPUT $action INTO #AccionesMerge;

    SELECT
        @FilasLeidas                                                                 AS FilasLeidas,
        ISNULL(SUM(CASE WHEN Accion = 'INSERT' THEN 1 ELSE 0 END), 0)                AS FilasInsertadas,
        ISNULL(SUM(CASE WHEN Accion = 'UPDATE' THEN 1 ELSE 0 END), 0)                AS FilasActualizadas,
        @FilasLeidas - ISNULL(SUM(CASE WHEN Accion = 'INSERT' THEN 1 ELSE 0 END), 0)
                      - ISNULL(SUM(CASE WHEN Accion = 'UPDATE' THEN 1 ELSE 0 END), 0) AS FilasIgnoradas
    FROM #AccionesMerge;

    DROP TABLE #Origen;
END
GO

CREATE OR ALTER PROCEDURE [int].usp_MergeDimHuaweiDevices
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.dimHuaweiDevices);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH StgDeduplicado AS (
        SELECT s.*,
               ROW_NUMBER() OVER (PARTITION BY RTRIM(s.DeviceId) ORDER BY (SELECT NULL)) AS rn
        FROM stg.dimHuaweiDevices s
        WHERE RTRIM(ISNULL(s.DeviceId, '')) <> '' AND RTRIM(ISNULL(s.StationCode, '')) <> ''
    ),
    StgNormalizado AS (
        SELECT
            RTRIM(s.DeviceId)                       AS DeviceId,
            RTRIM(s.StationCode)                    AS StationCode,
            NULLIF(RTRIM(s.DeviceEsn), '')          AS DeviceEsn,
            NULLIF(RTRIM(s.DeviceName), '')         AS DeviceName,
            s.DeviceTypeId,
            NULLIF(RTRIM(s.Model), '')              AS Model,
            NULLIF(RTRIM(s.SoftwareVersion), '')    AS SoftwareVersion,
            s.OptimizerNumber,
            NULLIF(RTRIM(s.InvType), '')            AS InvType,
            s.Longitude,
            s.Latitude,
            s.IsGenerator,
            NULLIF(RTRIM(s.Account), '')            AS Account,
            cap.InstalledCapacityKwp
        FROM StgDeduplicado s
        -- 258: capacidad que informa el portal en el hecho (KpiData.installed_capacity), ultimo valor > 0
        OUTER APPLY (
            SELECT TOP (1) v.Kwp AS InstalledCapacityKwp
            FROM stg.factHuaweiEnergyAndPowerPv f
            CROSS APPLY (SELECT TRY_CONVERT(DECIMAL(12,3),
                                 CASE WHEN ISJSON(f.KpiData) = 1 THEN JSON_VALUE(f.KpiData, '$.installed_capacity') END) AS Kwp) v
            WHERE RTRIM(f.DeviceId) = RTRIM(s.DeviceId) AND ISNULL(f.IsDeleted, 0) = 0 AND v.Kwp > 0
            ORDER BY f.[Time] DESC
        ) cap
        WHERE s.rn = 1
    ),
    StgConHash AS (
        SELECT
            n.*,
            HASHBYTES('SHA2_256', (SELECT n.* FOR XML RAW, BINARY BASE64)) AS HashDiff
        FROM StgNormalizado n
    )
    MERGE [int].dimHuaweiDevices AS destino
        USING StgConHash AS origen
        ON destino.DeviceId = origen.DeviceId
    WHEN MATCHED AND destino.HashDiff <> origen.HashDiff THEN
        UPDATE SET
            StationCode      = origen.StationCode,
            DeviceEsn        = origen.DeviceEsn,
            DeviceName       = origen.DeviceName,
            DeviceTypeId     = origen.DeviceTypeId,
            Model            = origen.Model,
            SoftwareVersion  = origen.SoftwareVersion,
            OptimizerNumber  = origen.OptimizerNumber,
            InvType          = origen.InvType,
            Longitude        = origen.Longitude,
            Latitude         = origen.Latitude,
            IsGenerator      = origen.IsGenerator,
            Account          = origen.Account,
            InstalledCapacityKwp = origen.InstalledCapacityKwp,
            EsVigente        = 1,
            HashDiff         = origen.HashDiff,
            FechaCargaInt    = SYSDATETIME(),
            RunId            = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (
            DeviceId, StationCode, DeviceEsn, DeviceName, DeviceTypeId, Model,
            SoftwareVersion, OptimizerNumber, InvType, Longitude, Latitude, IsGenerator, Account, InstalledCapacityKwp, HashDiff, RunId
        )
        VALUES (
            origen.DeviceId, origen.StationCode, origen.DeviceEsn, origen.DeviceName, origen.DeviceTypeId,
            origen.Model, origen.SoftwareVersion, origen.OptimizerNumber, origen.InvType, origen.Longitude,
            origen.Latitude, origen.IsGenerator, origen.Account, origen.InstalledCapacityKwp, origen.HashDiff, @RunId
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

CREATE OR ALTER PROCEDURE dw.usp_MergeDimHuaweiDevices
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH Origen AS (
        SELECT
            st.HuaweiStationKey,
            d.StationCode,
            d.DeviceId,
            d.DeviceEsn,
            d.DeviceName,
            d.DeviceTypeId,
            d.Model,
            d.SoftwareVersion,
            d.OptimizerNumber,
            d.InvType,
            d.Longitude,
            d.Latitude,
            d.IsGenerator,
            d.Account,
            d.InstalledCapacityKwp,
            d.EsVigente,
            d.HashDiff
        FROM [int].dimHuaweiDevices d
        JOIN dw.dimHuaweiStations st ON st.StationCode = d.StationCode
    )
    SELECT * INTO #Origen FROM Origen;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM #Origen);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    MERGE dw.dimHuaweiDevices AS destino
        USING #Origen AS origen
        ON destino.DeviceId = origen.DeviceId
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente) THEN
        UPDATE SET
            HuaweiStationKey  = origen.HuaweiStationKey,
            StationCode       = origen.StationCode,
            DeviceEsn         = origen.DeviceEsn,
            DeviceName        = origen.DeviceName,
            DeviceTypeId      = origen.DeviceTypeId,
            Model             = origen.Model,
            SoftwareVersion   = origen.SoftwareVersion,
            OptimizerNumber   = origen.OptimizerNumber,
            InvType           = origen.InvType,
            Longitude         = origen.Longitude,
            Latitude          = origen.Latitude,
            IsGenerator       = origen.IsGenerator,
            Account           = origen.Account,
            InstalledCapacityKwp = origen.InstalledCapacityKwp,
            EsVigente         = origen.EsVigente,
            HashDiff          = origen.HashDiff,
            FechaCargaDw      = SYSDATETIME(),
            RunId             = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (
            HuaweiStationKey, StationCode, DeviceId, DeviceEsn, DeviceName, DeviceTypeId, Model,
            SoftwareVersion, OptimizerNumber, InvType, Longitude, Latitude, IsGenerator, Account, InstalledCapacityKwp, EsVigente, HashDiff, RunId
        )
        VALUES (
            origen.HuaweiStationKey, origen.StationCode, origen.DeviceId, origen.DeviceEsn, origen.DeviceName,
            origen.DeviceTypeId, origen.Model, origen.SoftwareVersion, origen.OptimizerNumber, origen.InvType,
            origen.Longitude, origen.Latitude, origen.IsGenerator, origen.Account, origen.InstalledCapacityKwp, origen.EsVigente, origen.HashDiff, @RunId
        )
    OUTPUT $action INTO #AccionesMerge;

    SELECT
        @FilasLeidas                                                                 AS FilasLeidas,
        ISNULL(SUM(CASE WHEN Accion = 'INSERT' THEN 1 ELSE 0 END), 0)                AS FilasInsertadas,
        ISNULL(SUM(CASE WHEN Accion = 'UPDATE' THEN 1 ELSE 0 END), 0)                AS FilasActualizadas,
        @FilasLeidas - ISNULL(SUM(CASE WHEN Accion = 'INSERT' THEN 1 ELSE 0 END), 0)
                      - ISNULL(SUM(CASE WHEN Accion = 'UPDATE' THEN 1 ELSE 0 END), 0) AS FilasIgnoradas
    FROM #AccionesMerge;

    DROP TABLE #Origen;
END
GO

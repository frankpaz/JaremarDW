-- 257: los merge de Huawei (silver y gold de estaciones, equipos y hecho) copian Account (ver 256).
-- Mismos procedimientos que 047/049/051/053/136/138, solo se agrega la columna. En silver Account entra
-- al HashDiff: en la primera corrida se actualizan todas las estaciones y equipos (FULL).

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
            TRY_CONVERT(DATETIMEOFFSET(7), s.GridConnectionDate) AS GridConnectionDate,
            NULLIF(RTRIM(s.Account), '')                AS Account
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
            Account             = origen.Account,
            EsVigente           = 1,
            HashDiff            = origen.HashDiff,
            FechaCargaInt       = SYSDATETIME(),
            RunId               = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (
            StationCode, StationName, StationAddress, Longitude, Latitude, Capacity,
            ContactPerson, ContactMethod, GridConnectionDate, Account, HashDiff, RunId
        )
        VALUES (
            origen.StationCode, origen.StationName, origen.StationAddress, origen.Longitude, origen.Latitude,
            origen.Capacity, origen.ContactPerson, origen.ContactMethod, origen.GridConnectionDate, origen.Account, origen.HashDiff, @RunId
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
            ContactPerson, ContactMethod, GridConnectionDate, Account, EsVigente, HashDiff
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
            Account             = origen.Account,
            EsVigente           = origen.EsVigente,
            HashDiff            = origen.HashDiff,
            FechaCargaDw        = SYSDATETIME(),
            RunId               = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (
            StationCode, StationName, StationAddress, Longitude, Latitude, Capacity,
            ContactPerson, ContactMethod, GridConnectionDate, Account, EsVigente, HashDiff, RunId
        )
        VALUES (
            origen.StationCode, origen.StationName, origen.StationAddress, origen.Longitude, origen.Latitude,
            origen.Capacity, origen.ContactPerson, origen.ContactMethod, origen.GridConnectionDate, origen.Account,
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
            NULLIF(RTRIM(s.Account), '')            AS Account
        FROM StgDeduplicado s
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
            EsVigente        = 1,
            HashDiff         = origen.HashDiff,
            FechaCargaInt    = SYSDATETIME(),
            RunId            = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (
            DeviceId, StationCode, DeviceEsn, DeviceName, DeviceTypeId, Model,
            SoftwareVersion, OptimizerNumber, InvType, Longitude, Latitude, IsGenerator, Account, HashDiff, RunId
        )
        VALUES (
            origen.DeviceId, origen.StationCode, origen.DeviceEsn, origen.DeviceName, origen.DeviceTypeId,
            origen.Model, origen.SoftwareVersion, origen.OptimizerNumber, origen.InvType, origen.Longitude,
            origen.Latitude, origen.IsGenerator, origen.Account, origen.HashDiff, @RunId
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
            EsVigente         = origen.EsVigente,
            HashDiff          = origen.HashDiff,
            FechaCargaDw      = SYSDATETIME(),
            RunId             = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (
            HuaweiStationKey, StationCode, DeviceId, DeviceEsn, DeviceName, DeviceTypeId, Model,
            SoftwareVersion, OptimizerNumber, InvType, Longitude, Latitude, IsGenerator, Account, EsVigente, HashDiff, RunId
        )
        VALUES (
            origen.HuaweiStationKey, origen.StationCode, origen.DeviceId, origen.DeviceEsn, origen.DeviceName,
            origen.DeviceTypeId, origen.Model, origen.SoftwareVersion, origen.OptimizerNumber, origen.InvType,
            origen.Longitude, origen.Latitude, origen.IsGenerator, origen.Account, origen.EsVigente, origen.HashDiff, @RunId
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

CREATE OR ALTER PROCEDURE [int].usp_MergeFactHuaweiEnergyAndPowerPv
    @RunId            INT,
    @UltimoWatermark  DATETIME2(7) = NULL,
    @NuevoWatermark   DATETIME2(7) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Desde DATETIME2(3) = CONVERT(DATETIME2(3), ISNULL(@UltimoWatermark, '1900-01-01'));

    ;WITH StgIncremental AS (
        SELECT s.*
        FROM stg.factHuaweiEnergyAndPowerPv s
        WHERE CONVERT(DATETIME2(3), s.CreationTime) > @Desde
           OR CONVERT(DATETIME2(3), s.LastModificationTime) > @Desde
    ),
    StgDeduplicado AS (
        SELECT s.*,
               ROW_NUMBER() OVER (PARTITION BY s.Id ORDER BY (SELECT NULL)) AS rn
        FROM StgIncremental s
    ),
    StgNormalizado AS (
        SELECT
            s.Id,
            RTRIM(s.DeviceId)                                                  AS DeviceId,
            DATEADD(SECOND, s.Time / 1000, '1970-01-01')                       AS Time,
            TRY_CONVERT(DECIMAL(18,3), JSON_VALUE(s.KpiData, '$.product_power'))      AS ProductPower,
            s.CreationTime,
            s.LastModificationTime,
            s.IsDeleted,
            NULLIF(RTRIM(s.Account), '')                                       AS Account
        FROM StgDeduplicado s
        WHERE s.rn = 1
    ),
    StgConHash AS (
        SELECT
            n.*,
            HASHBYTES('SHA2_256', (SELECT n.* FOR XML RAW, BINARY BASE64)) AS HashDiff
        FROM StgNormalizado n
    )
    SELECT * INTO #Origen FROM StgConHash;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM #Origen);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    MERGE [int].factHuaweiEnergyAndPowerPv AS destino
        USING #Origen AS origen
        ON destino.Id = origen.Id
    WHEN MATCHED AND destino.HashDiff <> origen.HashDiff THEN
        UPDATE SET
            DeviceId               = origen.DeviceId,
            Time                    = origen.Time,
            ProductPower            = origen.ProductPower,
            CreationTime            = origen.CreationTime,
            LastModificationTime    = origen.LastModificationTime,
            IsDeleted               = origen.IsDeleted,
            Account                 = origen.Account,
            HashDiff                = origen.HashDiff,
            FechaCargaInt           = SYSDATETIME(),
            RunId                   = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (Id, DeviceId, Time, ProductPower, CreationTime, LastModificationTime, IsDeleted, Account, HashDiff, RunId)
        VALUES (origen.Id, origen.DeviceId, origen.Time, origen.ProductPower,
                origen.CreationTime, origen.LastModificationTime, origen.IsDeleted, origen.Account, origen.HashDiff, @RunId)
    OUTPUT $action INTO #AccionesMerge;

    SELECT @NuevoWatermark = CONVERT(DATETIME2(3), MAX(v.Marca))
    FROM (
        SELECT CreationTime AS Marca FROM #Origen
        UNION ALL
        SELECT LastModificationTime FROM #Origen WHERE LastModificationTime IS NOT NULL
    ) v;
    SET @NuevoWatermark = ISNULL(@NuevoWatermark, @Desde);

    SELECT
        @FilasLeidas                                                                 AS FilasLeidas,
        ISNULL(SUM(CASE WHEN Accion = 'INSERT' THEN 1 ELSE 0 END), 0)                AS FilasInsertadas,
        ISNULL(SUM(CASE WHEN Accion = 'UPDATE' THEN 1 ELSE 0 END), 0)                AS FilasActualizadas,
        @FilasLeidas - ISNULL(SUM(CASE WHEN Accion = 'INSERT' THEN 1 ELSE 0 END), 0)
                      - ISNULL(SUM(CASE WHEN Accion = 'UPDATE' THEN 1 ELSE 0 END), 0) AS FilasIgnoradas,
        @NuevoWatermark                                                              AS NuevoWatermark
    FROM #AccionesMerge;

    DROP TABLE #Origen;
END
GO

CREATE OR ALTER PROCEDURE dw.usp_MergeFactHuaweiEnergyAndPowerPv
    @RunId            INT,
    @UltimoWatermark  DATETIME2(7) = NULL,
    @NuevoWatermark   DATETIME2(7) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Desde DATETIME2(3) = CONVERT(DATETIME2(3), ISNULL(@UltimoWatermark, '1900-01-01'));

    ;WITH Origen AS (
        SELECT
            f.Id,
            d.HuaweiDeviceKey,
            f.DeviceId,
            f.Time,
            f.ProductPower,
            f.CreationTime,
            f.LastModificationTime,
            f.IsDeleted,
            f.Account,
            f.HashDiff,
            f.FechaCargaInt
        FROM [int].factHuaweiEnergyAndPowerPv f
        LEFT JOIN dw.dimHuaweiDevices d ON d.DeviceId = f.DeviceId
        WHERE CONVERT(DATETIME2(3), f.FechaCargaInt) > @Desde AND f.IsDeleted = 0
    )
    SELECT * INTO #Origen FROM Origen;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM #Origen);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    MERGE dw.factHuaweiEnergyAndPowerPv AS destino
        USING #Origen AS origen
        ON destino.Id = origen.Id
    WHEN MATCHED AND destino.HashDiff <> origen.HashDiff THEN
        UPDATE SET
            HuaweiDeviceKey       = origen.HuaweiDeviceKey,
            DeviceId              = origen.DeviceId,
            Time                  = origen.Time,
            ProductPower          = origen.ProductPower,
            CreationTime          = origen.CreationTime,
            LastModificationTime  = origen.LastModificationTime,
            IsDeleted             = origen.IsDeleted,
            Account               = origen.Account,
            HashDiff              = origen.HashDiff,
            FechaCargaDw          = SYSDATETIME(),
            RunId                 = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (Id, HuaweiDeviceKey, DeviceId, Time, ProductPower, CreationTime,
                LastModificationTime, IsDeleted, Account, HashDiff, RunId)
        VALUES (origen.Id, origen.HuaweiDeviceKey, origen.DeviceId, origen.Time, origen.ProductPower,
                origen.CreationTime, origen.LastModificationTime, origen.IsDeleted, origen.Account, origen.HashDiff, @RunId)
    OUTPUT $action INTO #AccionesMerge;

    SELECT @NuevoWatermark = CONVERT(DATETIME2(3), MAX(FechaCargaInt)) FROM #Origen;
    SET @NuevoWatermark = ISNULL(@NuevoWatermark, @Desde);

    SELECT
        @FilasLeidas                                                                 AS FilasLeidas,
        ISNULL(SUM(CASE WHEN Accion = 'INSERT' THEN 1 ELSE 0 END), 0)                AS FilasInsertadas,
        ISNULL(SUM(CASE WHEN Accion = 'UPDATE' THEN 1 ELSE 0 END), 0)                AS FilasActualizadas,
        @FilasLeidas - ISNULL(SUM(CASE WHEN Accion = 'INSERT' THEN 1 ELSE 0 END), 0)
                      - ISNULL(SUM(CASE WHEN Accion = 'UPDATE' THEN 1 ELSE 0 END), 0) AS FilasIgnoradas,
        @NuevoWatermark                                                              AS NuevoWatermark
    FROM #AccionesMerge;

    DROP TABLE #Origen;
END
GO

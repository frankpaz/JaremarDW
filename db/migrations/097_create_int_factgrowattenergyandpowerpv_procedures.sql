-- 097: merge Bronze -> Silver para factGrowattEnergyAndPowerPv. INCREMENTAL,
-- mismo patron de watermark (truncado a milisegundo) que los demas facts
-- ABP del dominio Solar. Columnas planas, sin JSON que parsear.

CREATE OR ALTER PROCEDURE [int].usp_MergeFactGrowattEnergyAndPowerPv
    @RunId            INT,
    @UltimoWatermark  DATETIME2(7) = NULL,
    @NuevoWatermark   DATETIME2(7) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Desde DATETIME2(3) = CONVERT(DATETIME2(3), ISNULL(@UltimoWatermark, '1900-01-01'));

    ;WITH StgIncremental AS (
        SELECT s.*
        FROM stg.factGrowattEnergyAndPowerPv s
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
            RTRIM(s.DeviceId)                    AS DeviceId,
            s.Time,
            s.Status,
            NULLIF(RTRIM(s.StatusText), '')      AS StatusText,
            s.PowerToday,
            s.PowerTotal,
            s.EacToday,
            s.EacTotal,
            s.Pac,
            s.Ppv,
            s.Pf,
            s.Fac,
            s.VacR,
            s.VacS,
            s.VacT,
            s.IacR,
            s.IacS,
            s.IacT,
            s.PacR,
            s.PacS,
            s.PacT,
            s.Temperature1,
            s.Temperature2,
            s.Temperature3,
            s.WarnCode,
            s.FaultType,
            s.FaultCode1,
            s.FaultCode2,
            s.PvIso,
            s.Gfci,
            s.CreationTime,
            s.LastModificationTime,
            s.IsDeleted
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

    MERGE [int].factGrowattEnergyAndPowerPv AS destino
        USING #Origen AS origen
        ON destino.Id = origen.Id
    WHEN MATCHED AND destino.HashDiff <> origen.HashDiff THEN
        UPDATE SET
            DeviceId                = origen.DeviceId,
            Time                     = origen.Time,
            Status                   = origen.Status,
            StatusText               = origen.StatusText,
            PowerToday               = origen.PowerToday,
            PowerTotal               = origen.PowerTotal,
            EacToday                 = origen.EacToday,
            EacTotal                 = origen.EacTotal,
            Pac                      = origen.Pac,
            Ppv                      = origen.Ppv,
            Pf                       = origen.Pf,
            Fac                      = origen.Fac,
            VacR                     = origen.VacR,
            VacS                     = origen.VacS,
            VacT                     = origen.VacT,
            IacR                     = origen.IacR,
            IacS                     = origen.IacS,
            IacT                     = origen.IacT,
            PacR                     = origen.PacR,
            PacS                     = origen.PacS,
            PacT                     = origen.PacT,
            Temperature1             = origen.Temperature1,
            Temperature2             = origen.Temperature2,
            Temperature3             = origen.Temperature3,
            WarnCode                 = origen.WarnCode,
            FaultType                = origen.FaultType,
            FaultCode1               = origen.FaultCode1,
            FaultCode2               = origen.FaultCode2,
            PvIso                    = origen.PvIso,
            Gfci                     = origen.Gfci,
            CreationTime             = origen.CreationTime,
            LastModificationTime     = origen.LastModificationTime,
            IsDeleted                = origen.IsDeleted,
            HashDiff                 = origen.HashDiff,
            FechaCargaInt            = SYSDATETIME(),
            RunId                    = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (
            Id, DeviceId, Time, Status, StatusText, PowerToday, PowerTotal, EacToday, EacTotal,
            Pac, Ppv, Pf, Fac, VacR, VacS, VacT, IacR, IacS, IacT, PacR, PacS, PacT,
            Temperature1, Temperature2, Temperature3, WarnCode, FaultType, FaultCode1, FaultCode2,
            PvIso, Gfci, CreationTime, LastModificationTime, IsDeleted, HashDiff, RunId
        )
        VALUES (
            origen.Id, origen.DeviceId, origen.Time, origen.Status, origen.StatusText, origen.PowerToday,
            origen.PowerTotal, origen.EacToday, origen.EacTotal, origen.Pac, origen.Ppv, origen.Pf, origen.Fac,
            origen.VacR, origen.VacS, origen.VacT, origen.IacR, origen.IacS, origen.IacT, origen.PacR, origen.PacS,
            origen.PacT, origen.Temperature1, origen.Temperature2, origen.Temperature3, origen.WarnCode,
            origen.FaultType, origen.FaultCode1, origen.FaultCode2, origen.PvIso, origen.Gfci, origen.CreationTime,
            origen.LastModificationTime, origen.IsDeleted, origen.HashDiff, @RunId
        )
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

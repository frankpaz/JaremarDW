-- 099: merge Silver -> Gold para factGrowattEnergyAndPowerPv. INCREMENTAL,
-- mismo patron de watermark que los demas facts del dominio Solar.

CREATE OR ALTER PROCEDURE dw.usp_MergeFactGrowattEnergyAndPowerPv
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
            f.DeviceId,
            f.Time,
            f.Status,
            f.StatusText,
            f.PowerToday,
            f.PowerTotal,
            f.EacToday,
            f.EacTotal,
            f.Pac,
            f.Ppv,
            f.Pf,
            f.Fac,
            f.VacR,
            f.VacS,
            f.VacT,
            f.IacR,
            f.IacS,
            f.IacT,
            f.PacR,
            f.PacS,
            f.PacT,
            f.Temperature1,
            f.Temperature2,
            f.Temperature3,
            f.WarnCode,
            f.FaultType,
            f.FaultCode1,
            f.FaultCode2,
            f.PvIso,
            f.Gfci,
            f.CreationTime,
            f.LastModificationTime,
            f.IsDeleted,
            f.HashDiff,
            f.FechaCargaInt
        FROM [int].factGrowattEnergyAndPowerPv f
        WHERE CONVERT(DATETIME2(3), f.FechaCargaInt) > @Desde AND f.IsDeleted = 0
    )
    SELECT * INTO #Origen FROM Origen;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM #Origen);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    MERGE dw.factGrowattEnergyAndPowerPv AS destino
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
            FechaCargaDw             = SYSDATETIME(),
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

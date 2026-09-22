-- 045: merge Silver -> Gold para dimSmaDevices. SCD Tipo 1 (sobrescribe).
-- Resuelve SmaPlantaKey por PlantId contra dw.dimSmaPlants (debe cargarse
-- primero). Filas cuyo PlantId no tenga planta en dw se excluyen del conteo
-- de FilasLeidas via el INNER JOIN -- no deberian existir en la practica.

CREATE OR ALTER PROCEDURE dw.usp_MergeDimSmaDevices
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH Origen AS (
        SELECT
            p.SmaPlantaKey,
            d.PlantId,
            d.DeviceId,
            d.DeviceName,
            d.DeviceTimezone,
            d.DeviceType,
            d.Product,
            d.ProductId,
            d.Serial,
            d.Vendor,
            d.GeneratorPower,
            d.GeneratorPowerDc,
            d.IsActive,
            d.IsGenerator,
            d.EsVigente,
            d.HashDiff
        FROM [int].dimSmaDevices d
        JOIN dw.dimSmaPlants p ON p.PlantId = d.PlantId
    )
    SELECT * INTO #Origen FROM Origen;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM #Origen);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    MERGE dw.dimSmaDevices AS destino
        USING #Origen AS origen
        ON destino.DeviceId = origen.DeviceId
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente) THEN
        UPDATE SET
            SmaPlantaKey      = origen.SmaPlantaKey,
            PlantId           = origen.PlantId,
            DeviceName        = origen.DeviceName,
            DeviceTimezone    = origen.DeviceTimezone,
            DeviceType        = origen.DeviceType,
            Product           = origen.Product,
            ProductId         = origen.ProductId,
            Serial            = origen.Serial,
            Vendor            = origen.Vendor,
            GeneratorPower    = origen.GeneratorPower,
            GeneratorPowerDc  = origen.GeneratorPowerDc,
            IsActive          = origen.IsActive,
            IsGenerator       = origen.IsGenerator,
            EsVigente         = origen.EsVigente,
            HashDiff          = origen.HashDiff,
            FechaCargaDw      = SYSDATETIME(),
            RunId             = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (
            SmaPlantaKey, PlantId, DeviceId, DeviceName, DeviceTimezone, DeviceType, Product, ProductId,
            Serial, Vendor, GeneratorPower, GeneratorPowerDc, IsActive, IsGenerator, EsVigente, HashDiff, RunId
        )
        VALUES (
            origen.SmaPlantaKey, origen.PlantId, origen.DeviceId, origen.DeviceName, origen.DeviceTimezone,
            origen.DeviceType, origen.Product, origen.ProductId, origen.Serial, origen.Vendor,
            origen.GeneratorPower, origen.GeneratorPowerDc, origen.IsActive, origen.IsGenerator,
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

    DROP TABLE #Origen;
END
GO

-- 186: VehiculoKey en dw.factEnvios. Resuelve el camion del envio (ENCCAM = NumeroCamion)
-- contra dw.dimVehiculo.CodigoVehiculo, igual que factGuiasRemision (D100CM). Verificado en
-- produccion (2026-09-29): de 120.483 envios con camion resuelven 120.455 (99,98 %); los 28
-- restantes son 6 codigos que no existen en LCM (T47 con 23). Los ~91 k envios sin camion
-- quedan con VehiculoKey NULL.
--
-- factEnvios no tiene reconciliacion semanal (el extract ya es FULL), asi que la llegada
-- tardia de un vehiculo no se puede dejar a una pasada completa: en cada corrida, ademas de lo
-- nuevo en [int] (FechaCargaInt > watermark), el merge toma los envios cuya VehiculoKey en
-- gold no coincide con la que hoy resuelve la dimension. Asi la primera corrida despues de
-- esta migracion rellena todo el historico y las siguientes solo lo que cambie. El watermark
-- se sigue calculando solo con lo nuevo (esas filas extra son anteriores al watermark).
-- Idempotente. Compatible con SQL Server 2016.

IF COL_LENGTH('dw.factEnvios', 'VehiculoKey') IS NULL
    ALTER TABLE dw.factEnvios ADD VehiculoKey INT NULL
        CONSTRAINT FK_dw_factEnvios_dimVehiculo REFERENCES dw.dimVehiculo(VehiculoKey);
GO

CREATE OR ALTER PROCEDURE dw.usp_MergeFactEnvios
    @RunId            INT,
    @UltimoWatermark  DATETIME2(7) = NULL,
    @NuevoWatermark   DATETIME2(7) = NULL OUTPUT,
    @Reconciliar      BIT          = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Desde DATETIME2(3) = CONVERT(DATETIME2(3), ISNULL(@UltimoWatermark, '1900-01-01'));

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH Origen AS (
        SELECT
            i.ENCENV AS NumeroEnvio,
            i.ENCUSU AS UsuarioGenero,
            i.ENCDSP AS PantallaGeneracion,
            i.ENCFEC AS FechaGeneracion,
            i.ENCTIM AS HoraGeneracion,
            i.ENCCAM AS NumeroCamion,
            v.VehiculoKey,
            i.ENCPEC AS CapacidadCamionKgs,
            i.ENCCAD AS PropietarioCamion,
            i.ENCEMT AS NumeroMotorista,
            i.ENCEMN AS NombreMotorista,
            i.ENCEN1 AS NumeroEmpleado1,
            i.ENCED1 AS NombreEmpleado1,
            i.ENCEN2 AS NumeroEmpleado2,
            i.ENCED2 AS NombreEmpleado2,
            i.ENCEN3 AS NumeroEmpleado3,
            i.ENCED3 AS NombreEmpleado3,
            i.ENCEN4 AS NumeroEmpleado4,
            i.ENCED4 AS NombreEmpleado4,
            i.ENCROU AS CodigoRuta,
            i.ENCDER AS DescripcionRuta,
            i.ENCFEU AS FechaUltimaModificacion,
            i.ENCTIU AS HoraUltimaModificacion,
            i.ENCSTA AS EstatusEnvio,
            i.ENCPES AS PesoTotalEnvio,
            i.ENCPLA AS NumeroPlaca,
            i.ENCDT1 AS Dato1,
            i.ENCPT2 AS Dato2,
            i.EsVigente,
            i.HashDiff,
            i.FechaCargaInt
        FROM [int].factEnvios i
        LEFT JOIN dw.dimVehiculo v ON v.CodigoVehiculo = i.ENCCAM
        WHERE @Reconciliar = 1
           OR CONVERT(DATETIME2(3), i.FechaCargaInt) > @Desde
           OR EXISTS (SELECT 1 FROM dw.factEnvios d
                      WHERE d.NumeroEnvio = i.ENCENV
                        AND ISNULL(d.VehiculoKey, -1) <> ISNULL(v.VehiculoKey, -1))
    )
    SELECT * INTO #Origen FROM Origen;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM #Origen);

    MERGE dw.factEnvios AS destino
        USING #Origen AS origen
        ON destino.NumeroEnvio = origen.NumeroEnvio
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente
                      OR ISNULL(destino.VehiculoKey, -1) <> ISNULL(origen.VehiculoKey, -1)) THEN
        UPDATE SET
            UsuarioGenero           = origen.UsuarioGenero,
            PantallaGeneracion      = origen.PantallaGeneracion,
            FechaGeneracion         = origen.FechaGeneracion,
            HoraGeneracion          = origen.HoraGeneracion,
            NumeroCamion            = origen.NumeroCamion,
            VehiculoKey             = origen.VehiculoKey,
            CapacidadCamionKgs      = origen.CapacidadCamionKgs,
            PropietarioCamion       = origen.PropietarioCamion,
            NumeroMotorista         = origen.NumeroMotorista,
            NombreMotorista         = origen.NombreMotorista,
            NumeroEmpleado1         = origen.NumeroEmpleado1,
            NombreEmpleado1         = origen.NombreEmpleado1,
            NumeroEmpleado2         = origen.NumeroEmpleado2,
            NombreEmpleado2         = origen.NombreEmpleado2,
            NumeroEmpleado3         = origen.NumeroEmpleado3,
            NombreEmpleado3         = origen.NombreEmpleado3,
            NumeroEmpleado4         = origen.NumeroEmpleado4,
            NombreEmpleado4         = origen.NombreEmpleado4,
            CodigoRuta              = origen.CodigoRuta,
            DescripcionRuta         = origen.DescripcionRuta,
            FechaUltimaModificacion = origen.FechaUltimaModificacion,
            HoraUltimaModificacion  = origen.HoraUltimaModificacion,
            EstatusEnvio            = origen.EstatusEnvio,
            PesoTotalEnvio          = origen.PesoTotalEnvio,
            NumeroPlaca             = origen.NumeroPlaca,
            Dato1                   = origen.Dato1,
            Dato2                   = origen.Dato2,
            EsVigente               = origen.EsVigente,
            HashDiff                = origen.HashDiff,
            FechaCargaDw            = SYSDATETIME(),
            RunId                   = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (
            NumeroEnvio, UsuarioGenero, PantallaGeneracion, FechaGeneracion, HoraGeneracion,
            NumeroCamion, VehiculoKey, CapacidadCamionKgs, PropietarioCamion, NumeroMotorista, NombreMotorista,
            NumeroEmpleado1, NombreEmpleado1, NumeroEmpleado2, NombreEmpleado2,
            NumeroEmpleado3, NombreEmpleado3, NumeroEmpleado4, NombreEmpleado4,
            CodigoRuta, DescripcionRuta, FechaUltimaModificacion, HoraUltimaModificacion,
            EstatusEnvio, PesoTotalEnvio, NumeroPlaca, Dato1, Dato2,
            EsVigente, HashDiff, RunId
        )
        VALUES (
            origen.NumeroEnvio, origen.UsuarioGenero, origen.PantallaGeneracion, origen.FechaGeneracion, origen.HoraGeneracion,
            origen.NumeroCamion, origen.VehiculoKey, origen.CapacidadCamionKgs, origen.PropietarioCamion, origen.NumeroMotorista, origen.NombreMotorista,
            origen.NumeroEmpleado1, origen.NombreEmpleado1, origen.NumeroEmpleado2, origen.NombreEmpleado2,
            origen.NumeroEmpleado3, origen.NombreEmpleado3, origen.NumeroEmpleado4, origen.NombreEmpleado4,
            origen.CodigoRuta, origen.DescripcionRuta, origen.FechaUltimaModificacion, origen.HoraUltimaModificacion,
            origen.EstatusEnvio, origen.PesoTotalEnvio, origen.NumeroPlaca, origen.Dato1, origen.Dato2,
            origen.EsVigente, origen.HashDiff, @RunId
        )
    OUTPUT $action INTO #AccionesMerge;

    -- Solo lo nuevo avanza el watermark (las filas que entraron por VehiculoKey son anteriores).
    SELECT @NuevoWatermark = CONVERT(DATETIME2(3), MAX(FechaCargaInt))
    FROM #Origen WHERE CONVERT(DATETIME2(3), FechaCargaInt) > @Desde;
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

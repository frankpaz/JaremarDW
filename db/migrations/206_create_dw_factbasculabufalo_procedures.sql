-- 206: merge Silver -> Gold para factBasculaBufalo. SCD Tipo 1, MERGE por la llave de negocio (nunca borra).
-- Incremental igual que ventas/compras/envios: procesa las filas de [int] con FechaCargaInt >
-- watermark (truncado a milisegundo) y devuelve como NuevoWatermark el MAX(FechaCargaInt) visto.
-- Ademas toma las boletas cuya llave de dimension en gold ya no coincide con la que resuelve hoy
-- la dimension (llegada tardia de un codigo al catalogo), igual que VehiculoKey en envios (186);
-- esas filas no mueven el watermark. @Reconciliar = 1 recorre todo [int].
-- Compatible con SQL Server 2016.

CREATE OR ALTER PROCEDURE dw.usp_MergeFactBasculaBufalo
    @RunId            INT,
    @UltimoWatermark  DATETIME2(7) = NULL,
    @NuevoWatermark   DATETIME2(7) = NULL OUTPUT,
    @Reconciliar      BIT          = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Desde DATETIME2(3) = CONVERT(DATETIME2(3), ISNULL(@UltimoWatermark, '1900-01-01'));

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH Resuelto AS (
        SELECT
            bascula.BasculaKey AS BasculaKey,
            tipoboleta.TipoBoletaKey AS TipoBoletaKey,
            productobascula.ProductoBasculaKey AS ProductoBasculaKey,
            lugarorigen.LugarBasculaKey AS LugarOrigenKey,
            lugardestino.LugarBasculaKey AS LugarDestinoKey,
            i.[BASCIA] AS CodigoBascula,
            i.[NUMBOLET] AS NumeroBoleta,
            i.[FECHAGEN] AS FechaGeneracion,
            i.[HORAGEN] AS HoraGeneracionOrigen,
            CASE WHEN i.[HORAGEN] IS NULL OR i.[HORAGEN] = 0 THEN NULL WHEN i.[HORAGEN] < 2400 THEN TRY_CONVERT(TIME(0), STUFF(RIGHT('0000' + CONVERT(VARCHAR(6), CAST(i.[HORAGEN] AS INT)), 4), 3, 0, ':')) ELSE TRY_CONVERT(TIME(0), STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(6), CAST(i.[HORAGEN] AS INT)), 6), 3, 0, ':'), 6, 0, ':')) END AS HoraGeneracion,
            i.[BASCUSER] AS CodigoUsuarioBascula,
            i.[NUMENVIO] AS NumeroEnvio,
            i.[BOLETY] AS CodigoTipoBoleta,
            i.[NUMPLACA] AS NumeroPlaca,
            i.[MOTORITA] AS NombreMotorista,
            i.[ORIGEN] AS CodigoLugarOrigen,
            i.[NUMLUGAR] AS CodigoLugarDestino,
            i.[PESOGEMAN] AS PesoManifiesto,
            i.[PESOTARA] AS PesoTara,
            i.[FECHATAR] AS FechaTara,
            i.[HORATARA] AS HoraTara,
            i.[PESOBRUT] AS PesoBruto,
            i.[FECHBRUT] AS FechaBruto,
            i.[HORABRUT] AS HoraBruto,
            i.[PESONETO] AS PesoNeto,
            i.[DIFPESO] AS DiferenciaPeso,
            i.[RIMPRESO] AS Reimpreso,
            i.[ESTATUS] AS EstatusBoleta,
            i.[NUMPROD] AS CodigoProductoBascula,
            i.[NUMPROV] AS CodigoProveedorBascula,
            i.[MARCHAMO] AS Marchamos,
            i.[OBSERBA] AS Observaciones,
            i.[NUMDOCTS] AS NumerosDocumentos,
            i.[PESOAUDI] AS PesoAprobadoAuditoria,
            i.[BASAUDIT] AS AuditorAutorizo,
            i.[MONTAR1] AS BasculaTara1,
            i.[MONTAR2] AS BasculaTara2,
            i.[MONTAR3] AS BasculaTara3,
            i.[MOMBRU1] AS BasculaBruto1,
            i.[MOMBRU2] AS BasculaBruto2,
            i.[MOMBRU3] AS BasculaBruto3,
            i.[FECHATAR1] AS FechaTara1,
            i.[HORATARA1] AS HoraTara1,
            i.[PESOTARA1] AS PesoTara1,
            i.[FECHATAR2] AS FechaTara2,
            i.[HORATARA2] AS HoraTara2,
            i.[PESOTARA2] AS PesoTara2,
            i.[FECHATAR3] AS FechaTara3,
            i.[HORATARA3] AS HoraTara3,
            i.[PESOTARA3] AS PesoTara3,
            i.[FECHBRUT1] AS FechaBruto1,
            i.[HORABRUT1] AS HoraBruto1,
            i.[PESOBRUT1] AS PesoBruto1,
            i.[FECHBRUT2] AS FechaBruto2,
            i.[HORABRUT2] AS HoraBruto2,
            i.[PESOBRUT2] AS PesoBruto2,
            i.[FECHBRUT3] AS FechaBruto3,
            i.[HORABRUT3] AS HoraBruto3,
            i.[PESOBRUT3] AS PesoBruto3,
            i.[PESOGEMAN1] AS PesoManifiesto1,
            i.[PESOGEMAN2] AS PesoManifiesto2,
            i.[PESOGEMAN3] AS PesoManifiesto3,
            i.[PESONETO1] AS PesoNeto1,
            i.[PESONETO2] AS PesoNeto2,
            i.[PESONETO3] AS PesoNeto3,
            i.[DIFPESO1] AS DiferenciaPeso1,
            i.[DIFPESO2] AS DiferenciaPeso2,
            i.[DIFPESO3] AS DiferenciaPeso3,
            i.[MARCACAM] AS MarcaCamion,
            i.[COLORCAM] AS ColorCamion,
            i.[NUMDOCTO] AS NumeroDocumentoOrigen,
            i.[FECDCTOO] AS FechaDocumentoOrigen,
            i.[STATUS1] AS Estatus1,
            i.[STATUS2] AS Estatus2,
            i.[ENCARGADO] AS NombreOperador,
            i.[ONLINE] AS ModoConexion,
            i.[IDENTIN] AS IdentificadorEntrada,
            i.[IDENTOUT] AS IdentificadorSalida,
            i.Repeticiones,
            i.EsVigente,
            i.HashDiff,
            i.FechaAlta,
            i.FechaUltimoCambio,
            i.FechaCargaInt
        FROM [int].factBasculaBufalo i
        LEFT JOIN dw.dimBascula bascula ON bascula.CodigoBascula = i.[BASCIA]
        LEFT JOIN dw.dimTipoBoleta tipoboleta ON tipoboleta.CodigoTipoBoleta = i.[BOLETY]
        LEFT JOIN dw.dimProductoBascula productobascula ON productobascula.CodigoProductoBascula = i.[NUMPROD]
        LEFT JOIN dw.dimLugarBascula lugarorigen ON lugarorigen.CodigoLugar = i.[ORIGEN]
        LEFT JOIN dw.dimLugarBascula lugardestino ON lugardestino.CodigoLugar = i.[NUMLUGAR]
    )
    SELECT * INTO #Origen FROM Resuelto o
    WHERE @Reconciliar = 1
       OR CONVERT(DATETIME2(3), o.FechaCargaInt) > @Desde
       OR EXISTS (SELECT 1 FROM dw.factBasculaBufalo d
                  WHERE d.CodigoBascula = o.CodigoBascula AND d.NumeroBoleta = o.NumeroBoleta
                    AND d.FechaGeneracion = o.FechaGeneracion AND d.HoraGeneracionOrigen = o.HoraGeneracionOrigen
                    AND (ISNULL(d.BasculaKey, -1) <> ISNULL(o.BasculaKey, -1)
                        OR ISNULL(d.TipoBoletaKey, -1) <> ISNULL(o.TipoBoletaKey, -1)
                        OR ISNULL(d.ProductoBasculaKey, -1) <> ISNULL(o.ProductoBasculaKey, -1)
                        OR ISNULL(d.LugarOrigenKey, -1) <> ISNULL(o.LugarOrigenKey, -1)
                        OR ISNULL(d.LugarDestinoKey, -1) <> ISNULL(o.LugarDestinoKey, -1)));

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM #Origen);

    MERGE dw.factBasculaBufalo AS destino
        USING #Origen AS origen
        ON  destino.CodigoBascula = origen.CodigoBascula AND destino.NumeroBoleta = origen.NumeroBoleta
        AND destino.FechaGeneracion = origen.FechaGeneracion AND destino.HoraGeneracionOrigen = origen.HoraGeneracionOrigen
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente
                     OR ISNULL(destino.BasculaKey, -1) <> ISNULL(origen.BasculaKey, -1)
                     OR ISNULL(destino.TipoBoletaKey, -1) <> ISNULL(origen.TipoBoletaKey, -1)
                     OR ISNULL(destino.ProductoBasculaKey, -1) <> ISNULL(origen.ProductoBasculaKey, -1)
                     OR ISNULL(destino.LugarOrigenKey, -1) <> ISNULL(origen.LugarOrigenKey, -1)
                     OR ISNULL(destino.LugarDestinoKey, -1) <> ISNULL(origen.LugarDestinoKey, -1)) THEN
        UPDATE SET
            BasculaKey               = origen.BasculaKey,
            TipoBoletaKey            = origen.TipoBoletaKey,
            ProductoBasculaKey       = origen.ProductoBasculaKey,
            LugarOrigenKey           = origen.LugarOrigenKey,
            LugarDestinoKey          = origen.LugarDestinoKey,
            HoraGeneracion           = origen.HoraGeneracion,
            CodigoUsuarioBascula     = origen.CodigoUsuarioBascula,
            NumeroEnvio              = origen.NumeroEnvio,
            CodigoTipoBoleta         = origen.CodigoTipoBoleta,
            NumeroPlaca              = origen.NumeroPlaca,
            NombreMotorista          = origen.NombreMotorista,
            CodigoLugarOrigen        = origen.CodigoLugarOrigen,
            CodigoLugarDestino       = origen.CodigoLugarDestino,
            PesoManifiesto           = origen.PesoManifiesto,
            PesoTara                 = origen.PesoTara,
            FechaTara                = origen.FechaTara,
            HoraTara                 = origen.HoraTara,
            PesoBruto                = origen.PesoBruto,
            FechaBruto               = origen.FechaBruto,
            HoraBruto                = origen.HoraBruto,
            PesoNeto                 = origen.PesoNeto,
            DiferenciaPeso           = origen.DiferenciaPeso,
            Reimpreso                = origen.Reimpreso,
            EstatusBoleta            = origen.EstatusBoleta,
            CodigoProductoBascula    = origen.CodigoProductoBascula,
            CodigoProveedorBascula   = origen.CodigoProveedorBascula,
            Marchamos                = origen.Marchamos,
            Observaciones            = origen.Observaciones,
            NumerosDocumentos        = origen.NumerosDocumentos,
            PesoAprobadoAuditoria    = origen.PesoAprobadoAuditoria,
            AuditorAutorizo          = origen.AuditorAutorizo,
            BasculaTara1             = origen.BasculaTara1,
            BasculaTara2             = origen.BasculaTara2,
            BasculaTara3             = origen.BasculaTara3,
            BasculaBruto1            = origen.BasculaBruto1,
            BasculaBruto2            = origen.BasculaBruto2,
            BasculaBruto3            = origen.BasculaBruto3,
            FechaTara1               = origen.FechaTara1,
            HoraTara1                = origen.HoraTara1,
            PesoTara1                = origen.PesoTara1,
            FechaTara2               = origen.FechaTara2,
            HoraTara2                = origen.HoraTara2,
            PesoTara2                = origen.PesoTara2,
            FechaTara3               = origen.FechaTara3,
            HoraTara3                = origen.HoraTara3,
            PesoTara3                = origen.PesoTara3,
            FechaBruto1              = origen.FechaBruto1,
            HoraBruto1               = origen.HoraBruto1,
            PesoBruto1               = origen.PesoBruto1,
            FechaBruto2              = origen.FechaBruto2,
            HoraBruto2               = origen.HoraBruto2,
            PesoBruto2               = origen.PesoBruto2,
            FechaBruto3              = origen.FechaBruto3,
            HoraBruto3               = origen.HoraBruto3,
            PesoBruto3               = origen.PesoBruto3,
            PesoManifiesto1          = origen.PesoManifiesto1,
            PesoManifiesto2          = origen.PesoManifiesto2,
            PesoManifiesto3          = origen.PesoManifiesto3,
            PesoNeto1                = origen.PesoNeto1,
            PesoNeto2                = origen.PesoNeto2,
            PesoNeto3                = origen.PesoNeto3,
            DiferenciaPeso1          = origen.DiferenciaPeso1,
            DiferenciaPeso2          = origen.DiferenciaPeso2,
            DiferenciaPeso3          = origen.DiferenciaPeso3,
            MarcaCamion              = origen.MarcaCamion,
            ColorCamion              = origen.ColorCamion,
            NumeroDocumentoOrigen    = origen.NumeroDocumentoOrigen,
            FechaDocumentoOrigen     = origen.FechaDocumentoOrigen,
            Estatus1                 = origen.Estatus1,
            Estatus2                 = origen.Estatus2,
            NombreOperador           = origen.NombreOperador,
            ModoConexion             = origen.ModoConexion,
            IdentificadorEntrada     = origen.IdentificadorEntrada,
            IdentificadorSalida      = origen.IdentificadorSalida,
            Repeticiones             = origen.Repeticiones,
            EsVigente                = origen.EsVigente,
            HashDiff                 = origen.HashDiff,
            FechaAlta                = origen.FechaAlta,
            FechaUltimoCambio        = origen.FechaUltimoCambio,
            FechaCargaDw             = SYSDATETIME(),
            RunId                    = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (BasculaKey, TipoBoletaKey, ProductoBasculaKey, LugarOrigenKey, LugarDestinoKey, CodigoBascula, NumeroBoleta, FechaGeneracion, HoraGeneracionOrigen, HoraGeneracion, CodigoUsuarioBascula, NumeroEnvio, CodigoTipoBoleta, NumeroPlaca, NombreMotorista, CodigoLugarOrigen, CodigoLugarDestino, PesoManifiesto, PesoTara, FechaTara, HoraTara, PesoBruto, FechaBruto, HoraBruto, PesoNeto, DiferenciaPeso, Reimpreso, EstatusBoleta, CodigoProductoBascula, CodigoProveedorBascula, Marchamos, Observaciones, NumerosDocumentos, PesoAprobadoAuditoria, AuditorAutorizo, BasculaTara1, BasculaTara2, BasculaTara3, BasculaBruto1, BasculaBruto2, BasculaBruto3, FechaTara1, HoraTara1, PesoTara1, FechaTara2, HoraTara2, PesoTara2, FechaTara3, HoraTara3, PesoTara3, FechaBruto1, HoraBruto1, PesoBruto1, FechaBruto2, HoraBruto2, PesoBruto2, FechaBruto3, HoraBruto3, PesoBruto3, PesoManifiesto1, PesoManifiesto2, PesoManifiesto3, PesoNeto1, PesoNeto2, PesoNeto3, DiferenciaPeso1, DiferenciaPeso2, DiferenciaPeso3, MarcaCamion, ColorCamion, NumeroDocumentoOrigen, FechaDocumentoOrigen, Estatus1, Estatus2, NombreOperador, ModoConexion, IdentificadorEntrada, IdentificadorSalida, Repeticiones, EsVigente, HashDiff, FechaAlta, FechaUltimoCambio, RunId)
        VALUES (origen.BasculaKey, origen.TipoBoletaKey, origen.ProductoBasculaKey, origen.LugarOrigenKey, origen.LugarDestinoKey, origen.CodigoBascula, origen.NumeroBoleta, origen.FechaGeneracion, origen.HoraGeneracionOrigen, origen.HoraGeneracion, origen.CodigoUsuarioBascula, origen.NumeroEnvio, origen.CodigoTipoBoleta, origen.NumeroPlaca, origen.NombreMotorista, origen.CodigoLugarOrigen, origen.CodigoLugarDestino, origen.PesoManifiesto, origen.PesoTara, origen.FechaTara, origen.HoraTara, origen.PesoBruto, origen.FechaBruto, origen.HoraBruto, origen.PesoNeto, origen.DiferenciaPeso, origen.Reimpreso, origen.EstatusBoleta, origen.CodigoProductoBascula, origen.CodigoProveedorBascula, origen.Marchamos, origen.Observaciones, origen.NumerosDocumentos, origen.PesoAprobadoAuditoria, origen.AuditorAutorizo, origen.BasculaTara1, origen.BasculaTara2, origen.BasculaTara3, origen.BasculaBruto1, origen.BasculaBruto2, origen.BasculaBruto3, origen.FechaTara1, origen.HoraTara1, origen.PesoTara1, origen.FechaTara2, origen.HoraTara2, origen.PesoTara2, origen.FechaTara3, origen.HoraTara3, origen.PesoTara3, origen.FechaBruto1, origen.HoraBruto1, origen.PesoBruto1, origen.FechaBruto2, origen.HoraBruto2, origen.PesoBruto2, origen.FechaBruto3, origen.HoraBruto3, origen.PesoBruto3, origen.PesoManifiesto1, origen.PesoManifiesto2, origen.PesoManifiesto3, origen.PesoNeto1, origen.PesoNeto2, origen.PesoNeto3, origen.DiferenciaPeso1, origen.DiferenciaPeso2, origen.DiferenciaPeso3, origen.MarcaCamion, origen.ColorCamion, origen.NumeroDocumentoOrigen, origen.FechaDocumentoOrigen, origen.Estatus1, origen.Estatus2, origen.NombreOperador, origen.ModoConexion, origen.IdentificadorEntrada, origen.IdentificadorSalida, origen.Repeticiones, origen.EsVigente, origen.HashDiff, origen.FechaAlta, origen.FechaUltimoCambio, @RunId)
    OUTPUT $action INTO #AccionesMerge;

    -- Solo lo nuevo avanza el watermark (las filas que entraron por llave de dimension son anteriores).
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

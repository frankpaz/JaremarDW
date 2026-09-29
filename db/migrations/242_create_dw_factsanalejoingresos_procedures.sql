-- 242: merge Silver -> Gold para factSanAlejoIngresos (dominio SanAlejo). SCD Tipo 1, MERGE por la llave de
-- negocio (nunca borra). Incremental igual que factBasculaBufalo (206): procesa las filas de [int] con
-- FechaCargaInt > watermark y devuelve como NuevoWatermark el MAX(FechaCargaInt) visto; ademas toma los
-- documentos cuya llave de dimension en gold ya no coincide con la que resuelve hoy la dimension
-- (llegada tardia al catalogo), sin mover el watermark. @Reconciliar = 1 recorre todo [int].
-- Compatible con SQL Server 2016.

CREATE OR ALTER PROCEDURE dw.usp_MergeFactSanAlejoIngresos
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
            d0.EmpresaKey AS EmpresaKey,
            d1.SanAlejoProductoKey AS SanAlejoProductoKey,
            d2.SanAlejoLocalizacionKey AS SanAlejoLocalizacionKey,
            d3.SanAlejoTransportistaKey AS SanAlejoTransportistaKey,
            d4.SanAlejoClienteKey AS SanAlejoClienteKey,
            i.[CODCIA] AS CodigoEmpresa,
            i.[CODSUC] AS CodigoSucursal,
            i.[NUMDOC] AS NumeroDocumento,
            i.[FECDOC] AS FechaDocumento,
            i.[HORDOC] AS HoraDocumento,
            i.[PLACA] AS Placa,
            i.[NOMBRE] AS NombreVendedor,
            i.[CODCLI] AS CodigoCliente,
            i.[CONDUC] AS Conductor,
            i.[TIPOP] AS CodigoProducto,
            i.[COMEN1] AS Comentario1,
            i.[COMEN2] AS Comentario2,
            i.[COMEN3] AS Comentario3,
            i.[BRUTO] AS PesoBruto,
            i.[TARA] AS PesoTara,
            i.[NETO] AS PesoNeto,
            i.[CODTRA] AS CodigoTransportista,
            i.[CODLOC] AS CodigoLocalizacion,
            i.[SELLO1] AS Sello1,
            i.[SELLO2] AS Sello2,
            i.[SELLO3] AS Sello3,
            i.[SELLO4] AS Sello4,
            i.[SELLO5] AS Sello5,
            i.[SELLO6] AS Sello6,
            i.[SELLO7] AS Sello7,
            i.[SELLO8] AS Sello8,
            i.[SELLO9] AS Sello9,
            i.[USUARI] AS Usuario,
            i.[PORACI] AS PorcentajeAcidez,
            i.[PORHUM] AS PorcentajeHumedad,
            i.[REFDOC] AS DocumentoReferencia,
            i.[REFPES] AS PesoEnvioOrigen,
            i.[FECENV] AS FechaEnvioOrigen,
            i.[MARMOD] AS MarcaModificada,
            i.[USUMOD] AS UsuarioModifico,
            i.[FECMOD] AS FechaModificacion,
            i.[NUMTIK] AS NumeroControl,
            i.[FECSAL] AS FechaSalida,
            i.[HORSAL] AS HoraSalida,
            i.[CERTIF] AS Certificada,
            i.[MODEL] AS ModeloCertificacion,
            i.[PROSUS] AS ProductoSustentable,
            i.[BOLVEN] AS BoletaVenta,
            i.[NOPEDI] AS NumeroEnvio,
            i.[FEPEDI] AS FechaEnvio,
            i.[NUMFAC] AS NumeroFactura,
            i.[SEMAN] AS SemanaProceso,
            i.[PEROPR] AS PeriodoOperativo,
            i.[MESC] AS MesContable,
            i.[AÑOC] AS AnioContable,
            i.[P1NPLA] AS PlacaCabezal,
            i.[P2NPLAC] AS PlacaCisterna,
            i.[M1IDM] AS CodigoMotorista,
            i.[T1CTRA] AS CodigoTransportistaTexto,
            i.[CARAC1] AS CampoTexto1,
            i.[CARAC3] AS CampoTexto3,
            i.[CARAC5] AS CampoTexto5,
            i.[DIGIT1] AS CampoNumerico1,
            i.[DIGIT2] AS CampoNumerico2,
            i.[DIGIT6] AS CampoNumerico6,
            i.[DIGIT7] AS CampoNumerico7,
            i.[HORAB] AS HoraBruto,
            i.[HORAT] AS HoraTara,
            i.[FECHAT] AS FechaTara,
            i.[FECHAB] AS FechaBruto,
            i.[IDING] AS IdEntrada,
            i.[IDSAL] AS IdSalida,
            i.[CONRAC] AS ContarRacimos,
            i.[CONCAL] AS ControlarCalidad,
            i.Repeticiones,
            i.EsVigente,
            i.HashDiff,
            i.FechaAlta,
            i.FechaUltimoCambio,
            i.FechaCargaInt
        FROM [int].factSanAlejoIngresos i
        LEFT JOIN dw.dimEmpresas d0 ON d0.CodigoEmpresa = i.[CODCIA]
        LEFT JOIN dw.dimSanAlejoProducto d1 ON d1.CodigoProducto = i.[TIPOP]
        LEFT JOIN dw.dimSanAlejoLocalizacion d2 ON d2.CodigoEmpresa = i.[CODCIA] AND d2.CodigoLocalizacion = i.[CODLOC]
        LEFT JOIN dw.dimSanAlejoTransportista d3 ON d3.CodigoEmpresa = i.[CODCIA] AND d3.CodigoTransportista = i.[CODTRA]
        LEFT JOIN dw.dimSanAlejoCliente d4 ON d4.CodigoEmpresa = i.[CODCIA] AND d4.CodigoCliente = i.[CODCLI]
    )
    SELECT * INTO #Origen FROM Resuelto o
    WHERE @Reconciliar = 1
       OR CONVERT(DATETIME2(3), o.FechaCargaInt) > @Desde
       OR EXISTS (SELECT 1 FROM dw.factSanAlejoIngresos d
                  WHERE d.CodigoEmpresa = o.CodigoEmpresa AND d.NumeroDocumento = o.NumeroDocumento
                    AND (ISNULL(d.EmpresaKey, -1) <> ISNULL(o.EmpresaKey, -1)
                        OR ISNULL(d.SanAlejoProductoKey, -1) <> ISNULL(o.SanAlejoProductoKey, -1)
                        OR ISNULL(d.SanAlejoLocalizacionKey, -1) <> ISNULL(o.SanAlejoLocalizacionKey, -1)
                        OR ISNULL(d.SanAlejoTransportistaKey, -1) <> ISNULL(o.SanAlejoTransportistaKey, -1)
                        OR ISNULL(d.SanAlejoClienteKey, -1) <> ISNULL(o.SanAlejoClienteKey, -1)));

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM #Origen);

    MERGE dw.factSanAlejoIngresos AS destino
        USING #Origen AS origen
        ON destino.CodigoEmpresa = origen.CodigoEmpresa AND destino.NumeroDocumento = origen.NumeroDocumento
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente
                     OR ISNULL(destino.EmpresaKey, -1) <> ISNULL(origen.EmpresaKey, -1)
                     OR ISNULL(destino.SanAlejoProductoKey, -1) <> ISNULL(origen.SanAlejoProductoKey, -1)
                     OR ISNULL(destino.SanAlejoLocalizacionKey, -1) <> ISNULL(origen.SanAlejoLocalizacionKey, -1)
                     OR ISNULL(destino.SanAlejoTransportistaKey, -1) <> ISNULL(origen.SanAlejoTransportistaKey, -1)
                     OR ISNULL(destino.SanAlejoClienteKey, -1) <> ISNULL(origen.SanAlejoClienteKey, -1)) THEN
        UPDATE SET
            EmpresaKey                 = origen.EmpresaKey,
            SanAlejoProductoKey        = origen.SanAlejoProductoKey,
            SanAlejoLocalizacionKey    = origen.SanAlejoLocalizacionKey,
            SanAlejoTransportistaKey   = origen.SanAlejoTransportistaKey,
            SanAlejoClienteKey         = origen.SanAlejoClienteKey,
            CodigoSucursal             = origen.CodigoSucursal,
            FechaDocumento             = origen.FechaDocumento,
            HoraDocumento              = origen.HoraDocumento,
            Placa                      = origen.Placa,
            NombreVendedor             = origen.NombreVendedor,
            CodigoCliente              = origen.CodigoCliente,
            Conductor                  = origen.Conductor,
            CodigoProducto             = origen.CodigoProducto,
            Comentario1                = origen.Comentario1,
            Comentario2                = origen.Comentario2,
            Comentario3                = origen.Comentario3,
            PesoBruto                  = origen.PesoBruto,
            PesoTara                   = origen.PesoTara,
            PesoNeto                   = origen.PesoNeto,
            CodigoTransportista        = origen.CodigoTransportista,
            CodigoLocalizacion         = origen.CodigoLocalizacion,
            Sello1                     = origen.Sello1,
            Sello2                     = origen.Sello2,
            Sello3                     = origen.Sello3,
            Sello4                     = origen.Sello4,
            Sello5                     = origen.Sello5,
            Sello6                     = origen.Sello6,
            Sello7                     = origen.Sello7,
            Sello8                     = origen.Sello8,
            Sello9                     = origen.Sello9,
            Usuario                    = origen.Usuario,
            PorcentajeAcidez           = origen.PorcentajeAcidez,
            PorcentajeHumedad          = origen.PorcentajeHumedad,
            DocumentoReferencia        = origen.DocumentoReferencia,
            PesoEnvioOrigen            = origen.PesoEnvioOrigen,
            FechaEnvioOrigen           = origen.FechaEnvioOrigen,
            MarcaModificada            = origen.MarcaModificada,
            UsuarioModifico            = origen.UsuarioModifico,
            FechaModificacion          = origen.FechaModificacion,
            NumeroControl              = origen.NumeroControl,
            FechaSalida                = origen.FechaSalida,
            HoraSalida                 = origen.HoraSalida,
            Certificada                = origen.Certificada,
            ModeloCertificacion        = origen.ModeloCertificacion,
            ProductoSustentable        = origen.ProductoSustentable,
            BoletaVenta                = origen.BoletaVenta,
            NumeroEnvio                = origen.NumeroEnvio,
            FechaEnvio                 = origen.FechaEnvio,
            NumeroFactura              = origen.NumeroFactura,
            SemanaProceso              = origen.SemanaProceso,
            PeriodoOperativo           = origen.PeriodoOperativo,
            MesContable                = origen.MesContable,
            AnioContable               = origen.AnioContable,
            PlacaCabezal               = origen.PlacaCabezal,
            PlacaCisterna              = origen.PlacaCisterna,
            CodigoMotorista            = origen.CodigoMotorista,
            CodigoTransportistaTexto   = origen.CodigoTransportistaTexto,
            CampoTexto1                = origen.CampoTexto1,
            CampoTexto3                = origen.CampoTexto3,
            CampoTexto5                = origen.CampoTexto5,
            CampoNumerico1             = origen.CampoNumerico1,
            CampoNumerico2             = origen.CampoNumerico2,
            CampoNumerico6             = origen.CampoNumerico6,
            CampoNumerico7             = origen.CampoNumerico7,
            HoraBruto                  = origen.HoraBruto,
            HoraTara                   = origen.HoraTara,
            FechaTara                  = origen.FechaTara,
            FechaBruto                 = origen.FechaBruto,
            IdEntrada                  = origen.IdEntrada,
            IdSalida                   = origen.IdSalida,
            ContarRacimos              = origen.ContarRacimos,
            ControlarCalidad           = origen.ControlarCalidad,
            Repeticiones               = origen.Repeticiones,
            EsVigente                  = origen.EsVigente,
            HashDiff                   = origen.HashDiff,
            FechaAlta                  = origen.FechaAlta,
            FechaUltimoCambio          = origen.FechaUltimoCambio,
            FechaCargaDw               = SYSDATETIME(),
            RunId                      = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (EmpresaKey, SanAlejoProductoKey, SanAlejoLocalizacionKey, SanAlejoTransportistaKey, SanAlejoClienteKey, CodigoEmpresa, CodigoSucursal, NumeroDocumento, FechaDocumento, HoraDocumento, Placa, NombreVendedor, CodigoCliente, Conductor, CodigoProducto, Comentario1, Comentario2, Comentario3, PesoBruto, PesoTara, PesoNeto, CodigoTransportista, CodigoLocalizacion, Sello1, Sello2, Sello3, Sello4, Sello5, Sello6, Sello7, Sello8, Sello9, Usuario, PorcentajeAcidez, PorcentajeHumedad, DocumentoReferencia, PesoEnvioOrigen, FechaEnvioOrigen, MarcaModificada, UsuarioModifico, FechaModificacion, NumeroControl, FechaSalida, HoraSalida, Certificada, ModeloCertificacion, ProductoSustentable, BoletaVenta, NumeroEnvio, FechaEnvio, NumeroFactura, SemanaProceso, PeriodoOperativo, MesContable, AnioContable, PlacaCabezal, PlacaCisterna, CodigoMotorista, CodigoTransportistaTexto, CampoTexto1, CampoTexto3, CampoTexto5, CampoNumerico1, CampoNumerico2, CampoNumerico6, CampoNumerico7, HoraBruto, HoraTara, FechaTara, FechaBruto, IdEntrada, IdSalida, ContarRacimos, ControlarCalidad, Repeticiones, EsVigente, HashDiff, FechaAlta, FechaUltimoCambio, RunId)
        VALUES (origen.EmpresaKey, origen.SanAlejoProductoKey, origen.SanAlejoLocalizacionKey, origen.SanAlejoTransportistaKey, origen.SanAlejoClienteKey, origen.CodigoEmpresa, origen.CodigoSucursal, origen.NumeroDocumento, origen.FechaDocumento, origen.HoraDocumento, origen.Placa, origen.NombreVendedor, origen.CodigoCliente, origen.Conductor, origen.CodigoProducto, origen.Comentario1, origen.Comentario2, origen.Comentario3, origen.PesoBruto, origen.PesoTara, origen.PesoNeto, origen.CodigoTransportista, origen.CodigoLocalizacion, origen.Sello1, origen.Sello2, origen.Sello3, origen.Sello4, origen.Sello5, origen.Sello6, origen.Sello7, origen.Sello8, origen.Sello9, origen.Usuario, origen.PorcentajeAcidez, origen.PorcentajeHumedad, origen.DocumentoReferencia, origen.PesoEnvioOrigen, origen.FechaEnvioOrigen, origen.MarcaModificada, origen.UsuarioModifico, origen.FechaModificacion, origen.NumeroControl, origen.FechaSalida, origen.HoraSalida, origen.Certificada, origen.ModeloCertificacion, origen.ProductoSustentable, origen.BoletaVenta, origen.NumeroEnvio, origen.FechaEnvio, origen.NumeroFactura, origen.SemanaProceso, origen.PeriodoOperativo, origen.MesContable, origen.AnioContable, origen.PlacaCabezal, origen.PlacaCisterna, origen.CodigoMotorista, origen.CodigoTransportistaTexto, origen.CampoTexto1, origen.CampoTexto3, origen.CampoTexto5, origen.CampoNumerico1, origen.CampoNumerico2, origen.CampoNumerico6, origen.CampoNumerico7, origen.HoraBruto, origen.HoraTara, origen.FechaTara, origen.FechaBruto, origen.IdEntrada, origen.IdSalida, origen.ContarRacimos, origen.ControlarCalidad, origen.Repeticiones, origen.EsVigente, origen.HashDiff, origen.FechaAlta, origen.FechaUltimoCambio, @RunId)
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

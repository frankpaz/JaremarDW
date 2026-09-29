-- 234: merge Silver -> Gold para factSanAlejoFruta (dominio SanAlejo). SCD Tipo 1, MERGE por la llave de
-- negocio (nunca borra). Incremental igual que factBasculaBufalo (206): procesa las filas de [int] con
-- FechaCargaInt > watermark y devuelve como NuevoWatermark el MAX(FechaCargaInt) visto; ademas toma los
-- documentos cuya llave de dimension en gold ya no coincide con la que resuelve hoy la dimension
-- (llegada tardia al catalogo), sin mover el watermark. @Reconciliar = 1 recorre todo [int].
-- Compatible con SQL Server 2016.

CREATE OR ALTER PROCEDURE dw.usp_MergeFactSanAlejoFruta
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
            d5.SanAlejoProductorKey AS SanAlejoProductorKey,
            d6.SanAlejoFincaKey AS SanAlejoFincaKey,
            i.[CODCIA] AS CodigoEmpresa,
            i.[CODSUC] AS CodigoSucursal,
            i.[NUMDOC] AS NumeroDocumento,
            i.[NUMID] AS NumeroId,
            i.[FECDOC] AS FechaDocumento,
            i.[HORDOC] AS HoraDocumento,
            i.[FINCA] AS CodigoFinca,
            i.[CODO] AS CodigoCapataz,
            i.[LOTE1] AS Lote1,
            i.[RACL1] AS RacimosLote1,
            i.[SUEL1] AS SueltaLote1,
            i.[LOTE2] AS Lote2,
            i.[RACL2] AS RacimosLote2,
            i.[SUEL2] AS SueltaLote2,
            i.[LOTE3] AS Lote3,
            i.[RACL3] AS RacimosLote3,
            i.[SUEL3] AS SueltaLote3,
            i.[LOTE4] AS Lote4,
            i.[RACL4] AS RacimosLote4,
            i.[SUEL4] AS SueltaLote4,
            i.[LOTE5] AS Lote5,
            i.[RACL5] AS RacimosLote5,
            i.[SUEL5] AS SueltaLote5,
            i.[LOTE6] AS Lote6,
            i.[RACL6] AS RacimosLote6,
            i.[ALIAS1] AS AliasVagon1,
            i.[MALLA1] AS MallaVagon1,
            i.[ALIAS2] AS AliasVagon2,
            i.[MALLA2] AS MallaVagon2,
            i.[ALIAS3] AS AliasVagon3,
            i.[MALLA3] AS MallaVagon3,
            i.[ALIAS4] AS AliasVagon4,
            i.[MALLA4] AS MallaVagon4,
            i.[ALIAS5] AS AliasVagon5,
            i.[MALLA5] AS MallaVagon5,
            i.[LLENO1] AS LlenoVagon1,
            i.[LLENO2] AS LlenoVagon2,
            i.[LLENO3] AS LlenoVagon3,
            i.[LLENO4] AS LlenoVagon4,
            i.[LLENO5] AS LlenoVagon5,
            i.[PESOA] AS PesoVagon1,
            i.[PESOB] AS PesoVagon2,
            i.[PESOC] AS PesoVagon3,
            i.[PESOD] AS PesoVagon4,
            i.[PESOE] AS PesoVagon5,
            i.[CODPRO] AS CodigoProductor,
            i.[CODCLI] AS CodigoCliente,
            i.[CODLOC] AS CodigoLocalizacion,
            i.[SECTOR] AS SectorProductor,
            i.[CTACON] AS CuentaContable,
            i.[PLACA] AS Placa,
            i.[NOMBRE] AS NombreVendedor,
            i.[CONDUC] AS Conductor,
            i.[TIPOP] AS CodigoProducto,
            i.[TIPOF] AS TipoFruta,
            i.[PROCED] AS Procedencia,
            i.[COMEN1] AS Comentario1,
            i.[COMEN2] AS Comentario2,
            i.[CODTRA] AS CodigoTransportista,
            i.[UBICA] AS Ubicacion,
            i.[BRUTO] AS PesoBruto,
            i.[TARA] AS PesoTara,
            i.[NETO] AS PesoNeto,
            i.[SUELTA] AS FrutaSuelta,
            i.[VERDE] AS VerdeDuro,
            i.[VERDEC] AS VerdeCholoton,
            i.[MADURO] AS Maduro,
            i.[SOBMAD] AS SobreMaduro,
            i.[PASADO] AS Pasado,
            i.[PATLAR] AS PataLarga,
            i.[RAQUIS] AS Raquis,
            i.[RACDEV] AS RacimosDevueltos,
            i.[EFICI] AS Eficiencia,
            i.[FVERDE] AS FincaVerdeDuro,
            i.[FVERDC] AS FincaVerdeCholoton,
            i.[FMADUR] AS FincaMaduro,
            i.[FSOBMA] AS FincaSobreMaduro,
            i.[FPASAD] AS FincaPasado,
            i.[FPATLA] AS FincaPataLarga,
            i.[EVAPLA] AS EvaluadorPlanta,
            i.[EVAFCA] AS EvaluadorFinca,
            i.[RACPLA] AS RacimosPlanta,
            i.[SACPLA] AS SacosPlanta,
            i.[CONRAC] AS ContarRacimos,
            i.[CONCAL] AS ControlarCalidad,
            i.[FRUTAR] AS PesoFrutaRacimo,
            i.[FRUTAS] AS PesoFrutaSuelta,
            i.[REFDOC] AS DocumentoReferencia,
            i.[REFPES] AS PesoEnvioOrigen,
            i.[FECENV] AS FechaEnvioOrigen,
            i.[MARMOD] AS MarcaModificada,
            i.[USUMOD] AS UsuarioModifico,
            i.[FECMOD] AS FechaModificacion,
            i.[NUMTIK] AS NumeroControl,
            i.[PAGINM] AS PagoInmediato,
            i.[NOPEDI] AS NumeroEnvio,
            i.[FEPEDI] AS FechaEnvio,
            i.[FECFAC] AS FechaFactura,
            i.[CERTIF] AS Certificada,
            i.[MODEL] AS ModeloCertificacion,
            i.[PROSUS] AS ProductoSustentable,
            i.[CERRSP] AS CertificadaRSPO,
            i.[SUSRSP] AS SustentableRSPO,
            i.[ISCCOR] AS CorrelativoISCC,
            i.[RSPCOR] AS CorrelativoRSPO,
            i.[BOLVEN] AS BoletaVenta,
            i.[CARAC2] AS CampoTexto2,
            i.[CARAC3] AS CampoTexto3,
            i.[CARAC5] AS CampoTexto5,
            i.[CARAC6] AS CampoTexto6,
            i.[CARAC7] AS CampoTexto7,
            i.[DIGIT1] AS CampoNumerico1,
            i.[DIGIT5] AS CampoNumerico5,
            i.[DIGIT6] AS CampoNumerico6,
            i.[DIGIT7] AS CampoNumerico7,
            i.[PEROPR] AS PeriodoOperativo,
            i.[SEMAN] AS SemanaProceso,
            i.[MESC] AS MesContable,
            i.[AÑOC] AS AnioContable,
            i.[USUARI] AS Usuario,
            i.[PAGARA] AS PagarA,
            i.[HORAB] AS HoraBruto,
            i.[HORAT] AS HoraTara,
            i.[FECHAT] AS FechaTara,
            i.[FECHAB] AS FechaBruto,
            i.[IDING] AS IdEntrada,
            i.[IDSAL] AS IdSalida,
            i.Repeticiones,
            i.EsVigente,
            i.HashDiff,
            i.FechaAlta,
            i.FechaUltimoCambio,
            i.FechaCargaInt
        FROM [int].factSanAlejoFruta i
        LEFT JOIN dw.dimEmpresas d0 ON d0.CodigoEmpresa = i.[CODCIA]
        LEFT JOIN dw.dimSanAlejoProducto d1 ON d1.CodigoProducto = i.[TIPOP]
        LEFT JOIN dw.dimSanAlejoLocalizacion d2 ON d2.CodigoEmpresa = i.[CODCIA] AND d2.CodigoLocalizacion = i.[CODLOC]
        LEFT JOIN dw.dimSanAlejoTransportista d3 ON d3.CodigoEmpresa = i.[CODCIA] AND d3.CodigoTransportista = i.[CODTRA]
        LEFT JOIN dw.dimSanAlejoCliente d4 ON d4.CodigoEmpresa = i.[CODCIA] AND d4.CodigoCliente = i.[CODCLI]
        LEFT JOIN dw.dimSanAlejoProductor d5 ON d5.CodigoEmpresa = i.[CODCIA] AND d5.CodigoProductor = i.[CODPRO]
        LEFT JOIN dw.dimSanAlejoFinca d6 ON d6.CodigoEmpresa = i.[CODCIA] AND d6.CodigoFinca = i.[FINCA]
    )
    SELECT * INTO #Origen FROM Resuelto o
    WHERE @Reconciliar = 1
       OR CONVERT(DATETIME2(3), o.FechaCargaInt) > @Desde
       OR EXISTS (SELECT 1 FROM dw.factSanAlejoFruta d
                  WHERE d.CodigoEmpresa = o.CodigoEmpresa AND d.NumeroDocumento = o.NumeroDocumento
                    AND (ISNULL(d.EmpresaKey, -1) <> ISNULL(o.EmpresaKey, -1)
                        OR ISNULL(d.SanAlejoProductoKey, -1) <> ISNULL(o.SanAlejoProductoKey, -1)
                        OR ISNULL(d.SanAlejoLocalizacionKey, -1) <> ISNULL(o.SanAlejoLocalizacionKey, -1)
                        OR ISNULL(d.SanAlejoTransportistaKey, -1) <> ISNULL(o.SanAlejoTransportistaKey, -1)
                        OR ISNULL(d.SanAlejoClienteKey, -1) <> ISNULL(o.SanAlejoClienteKey, -1)
                        OR ISNULL(d.SanAlejoProductorKey, -1) <> ISNULL(o.SanAlejoProductorKey, -1)
                        OR ISNULL(d.SanAlejoFincaKey, -1) <> ISNULL(o.SanAlejoFincaKey, -1)));

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM #Origen);

    MERGE dw.factSanAlejoFruta AS destino
        USING #Origen AS origen
        ON destino.CodigoEmpresa = origen.CodigoEmpresa AND destino.NumeroDocumento = origen.NumeroDocumento
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente
                     OR ISNULL(destino.EmpresaKey, -1) <> ISNULL(origen.EmpresaKey, -1)
                     OR ISNULL(destino.SanAlejoProductoKey, -1) <> ISNULL(origen.SanAlejoProductoKey, -1)
                     OR ISNULL(destino.SanAlejoLocalizacionKey, -1) <> ISNULL(origen.SanAlejoLocalizacionKey, -1)
                     OR ISNULL(destino.SanAlejoTransportistaKey, -1) <> ISNULL(origen.SanAlejoTransportistaKey, -1)
                     OR ISNULL(destino.SanAlejoClienteKey, -1) <> ISNULL(origen.SanAlejoClienteKey, -1)
                     OR ISNULL(destino.SanAlejoProductorKey, -1) <> ISNULL(origen.SanAlejoProductorKey, -1)
                     OR ISNULL(destino.SanAlejoFincaKey, -1) <> ISNULL(origen.SanAlejoFincaKey, -1)) THEN
        UPDATE SET
            EmpresaKey                 = origen.EmpresaKey,
            SanAlejoProductoKey        = origen.SanAlejoProductoKey,
            SanAlejoLocalizacionKey    = origen.SanAlejoLocalizacionKey,
            SanAlejoTransportistaKey   = origen.SanAlejoTransportistaKey,
            SanAlejoClienteKey         = origen.SanAlejoClienteKey,
            SanAlejoProductorKey       = origen.SanAlejoProductorKey,
            SanAlejoFincaKey           = origen.SanAlejoFincaKey,
            CodigoSucursal             = origen.CodigoSucursal,
            NumeroId                   = origen.NumeroId,
            FechaDocumento             = origen.FechaDocumento,
            HoraDocumento              = origen.HoraDocumento,
            CodigoFinca                = origen.CodigoFinca,
            CodigoCapataz              = origen.CodigoCapataz,
            Lote1                      = origen.Lote1,
            RacimosLote1               = origen.RacimosLote1,
            SueltaLote1                = origen.SueltaLote1,
            Lote2                      = origen.Lote2,
            RacimosLote2               = origen.RacimosLote2,
            SueltaLote2                = origen.SueltaLote2,
            Lote3                      = origen.Lote3,
            RacimosLote3               = origen.RacimosLote3,
            SueltaLote3                = origen.SueltaLote3,
            Lote4                      = origen.Lote4,
            RacimosLote4               = origen.RacimosLote4,
            SueltaLote4                = origen.SueltaLote4,
            Lote5                      = origen.Lote5,
            RacimosLote5               = origen.RacimosLote5,
            SueltaLote5                = origen.SueltaLote5,
            Lote6                      = origen.Lote6,
            RacimosLote6               = origen.RacimosLote6,
            AliasVagon1                = origen.AliasVagon1,
            MallaVagon1                = origen.MallaVagon1,
            AliasVagon2                = origen.AliasVagon2,
            MallaVagon2                = origen.MallaVagon2,
            AliasVagon3                = origen.AliasVagon3,
            MallaVagon3                = origen.MallaVagon3,
            AliasVagon4                = origen.AliasVagon4,
            MallaVagon4                = origen.MallaVagon4,
            AliasVagon5                = origen.AliasVagon5,
            MallaVagon5                = origen.MallaVagon5,
            LlenoVagon1                = origen.LlenoVagon1,
            LlenoVagon2                = origen.LlenoVagon2,
            LlenoVagon3                = origen.LlenoVagon3,
            LlenoVagon4                = origen.LlenoVagon4,
            LlenoVagon5                = origen.LlenoVagon5,
            PesoVagon1                 = origen.PesoVagon1,
            PesoVagon2                 = origen.PesoVagon2,
            PesoVagon3                 = origen.PesoVagon3,
            PesoVagon4                 = origen.PesoVagon4,
            PesoVagon5                 = origen.PesoVagon5,
            CodigoProductor            = origen.CodigoProductor,
            CodigoCliente              = origen.CodigoCliente,
            CodigoLocalizacion         = origen.CodigoLocalizacion,
            SectorProductor            = origen.SectorProductor,
            CuentaContable             = origen.CuentaContable,
            Placa                      = origen.Placa,
            NombreVendedor             = origen.NombreVendedor,
            Conductor                  = origen.Conductor,
            CodigoProducto             = origen.CodigoProducto,
            TipoFruta                  = origen.TipoFruta,
            Procedencia                = origen.Procedencia,
            Comentario1                = origen.Comentario1,
            Comentario2                = origen.Comentario2,
            CodigoTransportista        = origen.CodigoTransportista,
            Ubicacion                  = origen.Ubicacion,
            PesoBruto                  = origen.PesoBruto,
            PesoTara                   = origen.PesoTara,
            PesoNeto                   = origen.PesoNeto,
            FrutaSuelta                = origen.FrutaSuelta,
            VerdeDuro                  = origen.VerdeDuro,
            VerdeCholoton              = origen.VerdeCholoton,
            Maduro                     = origen.Maduro,
            SobreMaduro                = origen.SobreMaduro,
            Pasado                     = origen.Pasado,
            PataLarga                  = origen.PataLarga,
            Raquis                     = origen.Raquis,
            RacimosDevueltos           = origen.RacimosDevueltos,
            Eficiencia                 = origen.Eficiencia,
            FincaVerdeDuro             = origen.FincaVerdeDuro,
            FincaVerdeCholoton         = origen.FincaVerdeCholoton,
            FincaMaduro                = origen.FincaMaduro,
            FincaSobreMaduro           = origen.FincaSobreMaduro,
            FincaPasado                = origen.FincaPasado,
            FincaPataLarga             = origen.FincaPataLarga,
            EvaluadorPlanta            = origen.EvaluadorPlanta,
            EvaluadorFinca             = origen.EvaluadorFinca,
            RacimosPlanta              = origen.RacimosPlanta,
            SacosPlanta                = origen.SacosPlanta,
            ContarRacimos              = origen.ContarRacimos,
            ControlarCalidad           = origen.ControlarCalidad,
            PesoFrutaRacimo            = origen.PesoFrutaRacimo,
            PesoFrutaSuelta            = origen.PesoFrutaSuelta,
            DocumentoReferencia        = origen.DocumentoReferencia,
            PesoEnvioOrigen            = origen.PesoEnvioOrigen,
            FechaEnvioOrigen           = origen.FechaEnvioOrigen,
            MarcaModificada            = origen.MarcaModificada,
            UsuarioModifico            = origen.UsuarioModifico,
            FechaModificacion          = origen.FechaModificacion,
            NumeroControl              = origen.NumeroControl,
            PagoInmediato              = origen.PagoInmediato,
            NumeroEnvio                = origen.NumeroEnvio,
            FechaEnvio                 = origen.FechaEnvio,
            FechaFactura               = origen.FechaFactura,
            Certificada                = origen.Certificada,
            ModeloCertificacion        = origen.ModeloCertificacion,
            ProductoSustentable        = origen.ProductoSustentable,
            CertificadaRSPO            = origen.CertificadaRSPO,
            SustentableRSPO            = origen.SustentableRSPO,
            CorrelativoISCC            = origen.CorrelativoISCC,
            CorrelativoRSPO            = origen.CorrelativoRSPO,
            BoletaVenta                = origen.BoletaVenta,
            CampoTexto2                = origen.CampoTexto2,
            CampoTexto3                = origen.CampoTexto3,
            CampoTexto5                = origen.CampoTexto5,
            CampoTexto6                = origen.CampoTexto6,
            CampoTexto7                = origen.CampoTexto7,
            CampoNumerico1             = origen.CampoNumerico1,
            CampoNumerico5             = origen.CampoNumerico5,
            CampoNumerico6             = origen.CampoNumerico6,
            CampoNumerico7             = origen.CampoNumerico7,
            PeriodoOperativo           = origen.PeriodoOperativo,
            SemanaProceso              = origen.SemanaProceso,
            MesContable                = origen.MesContable,
            AnioContable               = origen.AnioContable,
            Usuario                    = origen.Usuario,
            PagarA                     = origen.PagarA,
            HoraBruto                  = origen.HoraBruto,
            HoraTara                   = origen.HoraTara,
            FechaTara                  = origen.FechaTara,
            FechaBruto                 = origen.FechaBruto,
            IdEntrada                  = origen.IdEntrada,
            IdSalida                   = origen.IdSalida,
            Repeticiones               = origen.Repeticiones,
            EsVigente                  = origen.EsVigente,
            HashDiff                   = origen.HashDiff,
            FechaAlta                  = origen.FechaAlta,
            FechaUltimoCambio          = origen.FechaUltimoCambio,
            FechaCargaDw               = SYSDATETIME(),
            RunId                      = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (EmpresaKey, SanAlejoProductoKey, SanAlejoLocalizacionKey, SanAlejoTransportistaKey, SanAlejoClienteKey, SanAlejoProductorKey, SanAlejoFincaKey, CodigoEmpresa, CodigoSucursal, NumeroDocumento, NumeroId, FechaDocumento, HoraDocumento, CodigoFinca, CodigoCapataz, Lote1, RacimosLote1, SueltaLote1, Lote2, RacimosLote2, SueltaLote2, Lote3, RacimosLote3, SueltaLote3, Lote4, RacimosLote4, SueltaLote4, Lote5, RacimosLote5, SueltaLote5, Lote6, RacimosLote6, AliasVagon1, MallaVagon1, AliasVagon2, MallaVagon2, AliasVagon3, MallaVagon3, AliasVagon4, MallaVagon4, AliasVagon5, MallaVagon5, LlenoVagon1, LlenoVagon2, LlenoVagon3, LlenoVagon4, LlenoVagon5, PesoVagon1, PesoVagon2, PesoVagon3, PesoVagon4, PesoVagon5, CodigoProductor, CodigoCliente, CodigoLocalizacion, SectorProductor, CuentaContable, Placa, NombreVendedor, Conductor, CodigoProducto, TipoFruta, Procedencia, Comentario1, Comentario2, CodigoTransportista, Ubicacion, PesoBruto, PesoTara, PesoNeto, FrutaSuelta, VerdeDuro, VerdeCholoton, Maduro, SobreMaduro, Pasado, PataLarga, Raquis, RacimosDevueltos, Eficiencia, FincaVerdeDuro, FincaVerdeCholoton, FincaMaduro, FincaSobreMaduro, FincaPasado, FincaPataLarga, EvaluadorPlanta, EvaluadorFinca, RacimosPlanta, SacosPlanta, ContarRacimos, ControlarCalidad, PesoFrutaRacimo, PesoFrutaSuelta, DocumentoReferencia, PesoEnvioOrigen, FechaEnvioOrigen, MarcaModificada, UsuarioModifico, FechaModificacion, NumeroControl, PagoInmediato, NumeroEnvio, FechaEnvio, FechaFactura, Certificada, ModeloCertificacion, ProductoSustentable, CertificadaRSPO, SustentableRSPO, CorrelativoISCC, CorrelativoRSPO, BoletaVenta, CampoTexto2, CampoTexto3, CampoTexto5, CampoTexto6, CampoTexto7, CampoNumerico1, CampoNumerico5, CampoNumerico6, CampoNumerico7, PeriodoOperativo, SemanaProceso, MesContable, AnioContable, Usuario, PagarA, HoraBruto, HoraTara, FechaTara, FechaBruto, IdEntrada, IdSalida, Repeticiones, EsVigente, HashDiff, FechaAlta, FechaUltimoCambio, RunId)
        VALUES (origen.EmpresaKey, origen.SanAlejoProductoKey, origen.SanAlejoLocalizacionKey, origen.SanAlejoTransportistaKey, origen.SanAlejoClienteKey, origen.SanAlejoProductorKey, origen.SanAlejoFincaKey, origen.CodigoEmpresa, origen.CodigoSucursal, origen.NumeroDocumento, origen.NumeroId, origen.FechaDocumento, origen.HoraDocumento, origen.CodigoFinca, origen.CodigoCapataz, origen.Lote1, origen.RacimosLote1, origen.SueltaLote1, origen.Lote2, origen.RacimosLote2, origen.SueltaLote2, origen.Lote3, origen.RacimosLote3, origen.SueltaLote3, origen.Lote4, origen.RacimosLote4, origen.SueltaLote4, origen.Lote5, origen.RacimosLote5, origen.SueltaLote5, origen.Lote6, origen.RacimosLote6, origen.AliasVagon1, origen.MallaVagon1, origen.AliasVagon2, origen.MallaVagon2, origen.AliasVagon3, origen.MallaVagon3, origen.AliasVagon4, origen.MallaVagon4, origen.AliasVagon5, origen.MallaVagon5, origen.LlenoVagon1, origen.LlenoVagon2, origen.LlenoVagon3, origen.LlenoVagon4, origen.LlenoVagon5, origen.PesoVagon1, origen.PesoVagon2, origen.PesoVagon3, origen.PesoVagon4, origen.PesoVagon5, origen.CodigoProductor, origen.CodigoCliente, origen.CodigoLocalizacion, origen.SectorProductor, origen.CuentaContable, origen.Placa, origen.NombreVendedor, origen.Conductor, origen.CodigoProducto, origen.TipoFruta, origen.Procedencia, origen.Comentario1, origen.Comentario2, origen.CodigoTransportista, origen.Ubicacion, origen.PesoBruto, origen.PesoTara, origen.PesoNeto, origen.FrutaSuelta, origen.VerdeDuro, origen.VerdeCholoton, origen.Maduro, origen.SobreMaduro, origen.Pasado, origen.PataLarga, origen.Raquis, origen.RacimosDevueltos, origen.Eficiencia, origen.FincaVerdeDuro, origen.FincaVerdeCholoton, origen.FincaMaduro, origen.FincaSobreMaduro, origen.FincaPasado, origen.FincaPataLarga, origen.EvaluadorPlanta, origen.EvaluadorFinca, origen.RacimosPlanta, origen.SacosPlanta, origen.ContarRacimos, origen.ControlarCalidad, origen.PesoFrutaRacimo, origen.PesoFrutaSuelta, origen.DocumentoReferencia, origen.PesoEnvioOrigen, origen.FechaEnvioOrigen, origen.MarcaModificada, origen.UsuarioModifico, origen.FechaModificacion, origen.NumeroControl, origen.PagoInmediato, origen.NumeroEnvio, origen.FechaEnvio, origen.FechaFactura, origen.Certificada, origen.ModeloCertificacion, origen.ProductoSustentable, origen.CertificadaRSPO, origen.SustentableRSPO, origen.CorrelativoISCC, origen.CorrelativoRSPO, origen.BoletaVenta, origen.CampoTexto2, origen.CampoTexto3, origen.CampoTexto5, origen.CampoTexto6, origen.CampoTexto7, origen.CampoNumerico1, origen.CampoNumerico5, origen.CampoNumerico6, origen.CampoNumerico7, origen.PeriodoOperativo, origen.SemanaProceso, origen.MesContable, origen.AnioContable, origen.Usuario, origen.PagarA, origen.HoraBruto, origen.HoraTara, origen.FechaTara, origen.FechaBruto, origen.IdEntrada, origen.IdSalida, origen.Repeticiones, origen.EsVigente, origen.HashDiff, origen.FechaAlta, origen.FechaUltimoCambio, @RunId)
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

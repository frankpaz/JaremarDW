-- 139: Gold incremental real para factEnvios, factVentas y factCompras.
-- Antes dw.usp_MergeFact* recorria TODO [int] en cada corrida (COUNT(*) sobre
-- [int] + MERGE contra la tabla completa) y guardaba como watermark la hora
-- del cliente, que no se usaba. Ahora, igual que los hechos Solar, procesa
-- solo las filas de [int] con FechaCargaInt > watermark (truncado a
-- milisegundo) y devuelve como NuevoWatermark el MAX(FechaCargaInt) visto,
-- no la hora del cliente (evita desfases de reloj entre cliente y servidor).
--
-- @Reconciliar = 1 ignora el watermark y recorre todo [int] (reconciliacion
-- semanal). En ambos modos, una fila con EmpresaKey/ProductoKey/ProveedorKey
-- NULL en gold se actualiza en cuanto la dimension ya la resuelve (llegada
-- tardia de la dimension), algo que el HashDiff de [int] no detecta.
--
-- Los watermarks de gold se reinician a NULL: la primera corrida despues de
-- esta migracion hace una pasada completa de comparacion (sin escrituras si
-- nada cambio) y desde ahi avanza solo por FechaCargaInt.

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
            ENCENV AS NumeroEnvio,
            ENCUSU AS UsuarioGenero,
            ENCDSP AS PantallaGeneracion,
            ENCFEC AS FechaGeneracion,
            ENCTIM AS HoraGeneracion,
            ENCCAM AS NumeroCamion,
            ENCPEC AS CapacidadCamionKgs,
            ENCCAD AS PropietarioCamion,
            ENCEMT AS NumeroMotorista,
            ENCEMN AS NombreMotorista,
            ENCEN1 AS NumeroEmpleado1,
            ENCED1 AS NombreEmpleado1,
            ENCEN2 AS NumeroEmpleado2,
            ENCED2 AS NombreEmpleado2,
            ENCEN3 AS NumeroEmpleado3,
            ENCED3 AS NombreEmpleado3,
            ENCEN4 AS NumeroEmpleado4,
            ENCED4 AS NombreEmpleado4,
            ENCROU AS CodigoRuta,
            ENCDER AS DescripcionRuta,
            ENCFEU AS FechaUltimaModificacion,
            ENCTIU AS HoraUltimaModificacion,
            ENCSTA AS EstatusEnvio,
            ENCPES AS PesoTotalEnvio,
            ENCPLA AS NumeroPlaca,
            ENCDT1 AS Dato1,
            ENCPT2 AS Dato2,
            EsVigente,
            HashDiff,
            FechaCargaInt
        FROM [int].factEnvios
        WHERE @Reconciliar = 1 OR CONVERT(DATETIME2(3), FechaCargaInt) > @Desde
    )
    SELECT * INTO #Origen FROM Origen;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM #Origen);

    MERGE dw.factEnvios AS destino
        USING #Origen AS origen
        ON destino.NumeroEnvio = origen.NumeroEnvio
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente) THEN
        UPDATE SET
            UsuarioGenero           = origen.UsuarioGenero,
            PantallaGeneracion      = origen.PantallaGeneracion,
            FechaGeneracion         = origen.FechaGeneracion,
            HoraGeneracion          = origen.HoraGeneracion,
            NumeroCamion            = origen.NumeroCamion,
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
            NumeroCamion, CapacidadCamionKgs, PropietarioCamion, NumeroMotorista, NombreMotorista,
            NumeroEmpleado1, NombreEmpleado1, NumeroEmpleado2, NombreEmpleado2,
            NumeroEmpleado3, NombreEmpleado3, NumeroEmpleado4, NombreEmpleado4,
            CodigoRuta, DescripcionRuta, FechaUltimaModificacion, HoraUltimaModificacion,
            EstatusEnvio, PesoTotalEnvio, NumeroPlaca, Dato1, Dato2,
            EsVigente, HashDiff, RunId
        )
        VALUES (
            origen.NumeroEnvio, origen.UsuarioGenero, origen.PantallaGeneracion, origen.FechaGeneracion, origen.HoraGeneracion,
            origen.NumeroCamion, origen.CapacidadCamionKgs, origen.PropietarioCamion, origen.NumeroMotorista, origen.NombreMotorista,
            origen.NumeroEmpleado1, origen.NombreEmpleado1, origen.NumeroEmpleado2, origen.NombreEmpleado2,
            origen.NumeroEmpleado3, origen.NombreEmpleado3, origen.NumeroEmpleado4, origen.NombreEmpleado4,
            origen.CodigoRuta, origen.DescripcionRuta, origen.FechaUltimaModificacion, origen.HoraUltimaModificacion,
            origen.EstatusEnvio, origen.PesoTotalEnvio, origen.NumeroPlaca, origen.Dato1, origen.Dato2,
            origen.EsVigente, origen.HashDiff, @RunId
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

CREATE OR ALTER PROCEDURE dw.usp_MergeFactVentas
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
            ILCOMP AS NumeroEmpresa,
            ILDPFX AS PrefijoDocumento,
            ILDOCN AS NumeroDocumento,
            ILDYR AS AnioDocumento,
            ILDTYP AS TipoDocumento,
            ILLINE AS NumeroLinea,
            ILSEQ AS NumeroSecuencia,
            ILINVN AS NumeroDocumentoOriginal,
            ILORD AS NumeroOrden,
            ILDATE AS FechaUltimaTransaccion,
            ILSDTE AS FechaEnvio,
            ILPROD AS CodigoProducto,
            ILCUST AS NumeroCliente,
            ILCUSB AS NumeroClienteFacturacion,
            ILWHS AS Bodega,
            ILLTYP AS TipoLinea,
            ILOCLS AS ClaseOrden,
            ILQTY AS Cantidad,
            ILQINS AS CantidadUMVenta,
            ILNET AS PrecioNetoStocking,
            ILNETS AS PrecioNetoVenta,
            ILLIST AS PrecioListaTransaccion,
            ILBLST AS PrecioListaBase,
            ILEXTA AS MontoExtendido,
            ILREV AS MontoIngreso,
            ILPCST,
            ILUM AS UnidadMedida,
            ILSLUM AS UnidadMedidaVentaOriginal,
            ILCWUM AS UnidadMedidaPesoCatch,
            ILTR01 AS CodigoImpuesto1,
            ILTA01 AS MontoImpuesto1,
            ILTR02 AS CodigoImpuesto2,
            ILTA02 AS MontoImpuesto2,
            ILSAL1 AS Vendedor1,
            ILSAL3 AS Vendedor3,
            ILCCOM AS CodigoComisionCliente,
            ILCPO AS OrdenCompraCliente,
            ILCONS AS NumeroConsolidacion,
            ILNPSC AS CodigoFuentePrecioNeto,
            ILLPSC AS CodigoFuentePrecioLista,
            ILPFAC AS InstalacionPrecio,
            ILPKGG AS GrupoEmpaque,
            SICURR AS CodigoMoneda,
            SICNFC AS TasaCambioMoneda,
            SIGCNV AS TasaCambioGlobal,
            SITERM AS CodigoTerminos,
            SICARR AS Transportista,
            SIROUT AS Ruta,
            IHENDT AS FechaCreacion,
            IHENTM AS HoraCreacion,
            IHENUS AS UsuarioCreacion,
            EsVigente,
            HashDiff,
            FechaCargaInt
        FROM [int].factVentas
        WHERE @Reconciliar = 1 OR CONVERT(DATETIME2(3), FechaCargaInt) > @Desde
    ),
    OrigenConFk AS (
        SELECT o.*, e.EmpresaKey, p.ProductoKey
        FROM Origen o
        LEFT JOIN dw.dimEmpresas e ON e.CodigoEmpresa = RIGHT('00' + CONVERT(VARCHAR(2), o.NumeroEmpresa), 2)
        LEFT JOIN dw.dimProducto p ON p.CodigoProducto = o.CodigoProducto
    )
    SELECT * INTO #Origen FROM OrigenConFk;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM #Origen);

    MERGE dw.factVentas AS destino
        USING #Origen AS origen
        ON destino.NumeroEmpresa = origen.NumeroEmpresa AND destino.PrefijoDocumento = origen.PrefijoDocumento AND destino.NumeroDocumento = origen.NumeroDocumento AND destino.AnioDocumento = origen.AnioDocumento AND destino.TipoDocumento = origen.TipoDocumento AND destino.NumeroLinea = origen.NumeroLinea
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente
                    OR (destino.EmpresaKey IS NULL AND origen.EmpresaKey IS NOT NULL) OR (destino.ProductoKey IS NULL AND origen.ProductoKey IS NOT NULL)) THEN
        UPDATE SET
            NumeroEmpresa = origen.NumeroEmpresa,
            PrefijoDocumento = origen.PrefijoDocumento,
            NumeroDocumento = origen.NumeroDocumento,
            AnioDocumento = origen.AnioDocumento,
            TipoDocumento = origen.TipoDocumento,
            NumeroLinea = origen.NumeroLinea,
            NumeroSecuencia = origen.NumeroSecuencia,
            NumeroDocumentoOriginal = origen.NumeroDocumentoOriginal,
            NumeroOrden = origen.NumeroOrden,
            FechaUltimaTransaccion = origen.FechaUltimaTransaccion,
            FechaEnvio = origen.FechaEnvio,
            CodigoProducto = origen.CodigoProducto,
            NumeroCliente = origen.NumeroCliente,
            NumeroClienteFacturacion = origen.NumeroClienteFacturacion,
            Bodega = origen.Bodega,
            TipoLinea = origen.TipoLinea,
            ClaseOrden = origen.ClaseOrden,
            Cantidad = origen.Cantidad,
            CantidadUMVenta = origen.CantidadUMVenta,
            PrecioNetoStocking = origen.PrecioNetoStocking,
            PrecioNetoVenta = origen.PrecioNetoVenta,
            PrecioListaTransaccion = origen.PrecioListaTransaccion,
            PrecioListaBase = origen.PrecioListaBase,
            MontoExtendido = origen.MontoExtendido,
            MontoIngreso = origen.MontoIngreso,
            ILPCST = origen.ILPCST,
            UnidadMedida = origen.UnidadMedida,
            UnidadMedidaVentaOriginal = origen.UnidadMedidaVentaOriginal,
            UnidadMedidaPesoCatch = origen.UnidadMedidaPesoCatch,
            CodigoImpuesto1 = origen.CodigoImpuesto1,
            MontoImpuesto1 = origen.MontoImpuesto1,
            CodigoImpuesto2 = origen.CodigoImpuesto2,
            MontoImpuesto2 = origen.MontoImpuesto2,
            Vendedor1 = origen.Vendedor1,
            Vendedor3 = origen.Vendedor3,
            CodigoComisionCliente = origen.CodigoComisionCliente,
            OrdenCompraCliente = origen.OrdenCompraCliente,
            NumeroConsolidacion = origen.NumeroConsolidacion,
            CodigoFuentePrecioNeto = origen.CodigoFuentePrecioNeto,
            CodigoFuentePrecioLista = origen.CodigoFuentePrecioLista,
            InstalacionPrecio = origen.InstalacionPrecio,
            GrupoEmpaque = origen.GrupoEmpaque,
            CodigoMoneda = origen.CodigoMoneda,
            TasaCambioMoneda = origen.TasaCambioMoneda,
            TasaCambioGlobal = origen.TasaCambioGlobal,
            CodigoTerminos = origen.CodigoTerminos,
            Transportista = origen.Transportista,
            Ruta = origen.Ruta,
            FechaCreacion = origen.FechaCreacion,
            HoraCreacion = origen.HoraCreacion,
            UsuarioCreacion = origen.UsuarioCreacion,
            EmpresaKey   = origen.EmpresaKey,
            ProductoKey  = origen.ProductoKey,
            EsVigente    = origen.EsVigente,
            HashDiff     = origen.HashDiff,
            FechaCargaDw = SYSDATETIME(),
            RunId        = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (EmpresaKey, ProductoKey, NumeroEmpresa, PrefijoDocumento, NumeroDocumento, AnioDocumento, TipoDocumento, NumeroLinea, NumeroSecuencia, NumeroDocumentoOriginal, NumeroOrden, FechaUltimaTransaccion, FechaEnvio, CodigoProducto, NumeroCliente, NumeroClienteFacturacion, Bodega, TipoLinea, ClaseOrden, Cantidad, CantidadUMVenta, PrecioNetoStocking, PrecioNetoVenta, PrecioListaTransaccion, PrecioListaBase, MontoExtendido, MontoIngreso, ILPCST, UnidadMedida, UnidadMedidaVentaOriginal, UnidadMedidaPesoCatch, CodigoImpuesto1, MontoImpuesto1, CodigoImpuesto2, MontoImpuesto2, Vendedor1, Vendedor3, CodigoComisionCliente, OrdenCompraCliente, NumeroConsolidacion, CodigoFuentePrecioNeto, CodigoFuentePrecioLista, InstalacionPrecio, GrupoEmpaque, CodigoMoneda, TasaCambioMoneda, TasaCambioGlobal, CodigoTerminos, Transportista, Ruta, FechaCreacion, HoraCreacion, UsuarioCreacion, EsVigente, HashDiff, RunId)
        VALUES (origen.EmpresaKey, origen.ProductoKey, origen.NumeroEmpresa, origen.PrefijoDocumento, origen.NumeroDocumento, origen.AnioDocumento, origen.TipoDocumento, origen.NumeroLinea, origen.NumeroSecuencia, origen.NumeroDocumentoOriginal, origen.NumeroOrden, origen.FechaUltimaTransaccion, origen.FechaEnvio, origen.CodigoProducto, origen.NumeroCliente, origen.NumeroClienteFacturacion, origen.Bodega, origen.TipoLinea, origen.ClaseOrden, origen.Cantidad, origen.CantidadUMVenta, origen.PrecioNetoStocking, origen.PrecioNetoVenta, origen.PrecioListaTransaccion, origen.PrecioListaBase, origen.MontoExtendido, origen.MontoIngreso, origen.ILPCST, origen.UnidadMedida, origen.UnidadMedidaVentaOriginal, origen.UnidadMedidaPesoCatch, origen.CodigoImpuesto1, origen.MontoImpuesto1, origen.CodigoImpuesto2, origen.MontoImpuesto2, origen.Vendedor1, origen.Vendedor3, origen.CodigoComisionCliente, origen.OrdenCompraCliente, origen.NumeroConsolidacion, origen.CodigoFuentePrecioNeto, origen.CodigoFuentePrecioLista, origen.InstalacionPrecio, origen.GrupoEmpaque, origen.CodigoMoneda, origen.TasaCambioMoneda, origen.TasaCambioGlobal, origen.CodigoTerminos, origen.Transportista, origen.Ruta, origen.FechaCreacion, origen.HoraCreacion, origen.UsuarioCreacion, origen.EsVigente, origen.HashDiff, @RunId)
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

CREATE OR ALTER PROCEDURE dw.usp_MergeFactCompras
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
            PLCMPY AS NumeroEmpresa,
            PLDCPX AS PrefijoDocumento,
            PLDCYR AS AnioDocumento,
            PLDCSQ AS NumeroSecuenciaDocumento,
            PLLINE AS NumeroLinea,
            PLVNDR AS NumeroProveedor,
            PLINV AS NumeroFacturaReferencia,
            PLTYPE AS TipoLinea,
            PLGLDT AS FechaContable,
            PLAMT AS MontoPago,
            PLBAMT AS MontoPagoBase,
            PLDESC AS DescripcionFactura,
            PLUSER AS UsuarioCreacion,
            PLEDTE AS FechaCreacion,
            PLETIM AS HoraCreacion,
            PLRESN AS CodigoRazon,
            APHPND AS ProveedorPagoA,
            APHBNK AS CodigoBanco,
            APHCUR AS CodigoMoneda,
            APHOLD AS FacturaEnRetencion,
            AINVDT AS FechaFactura,
            ADUEDT AS FechaVencimiento,
            ADISCD AS FechaDescuento,
            APCINA AS MontoFacturaActual,
            APCAMP AS MontoPagadoActual,
            APCOUT AS SaldoPendiente,
            APPORD AS NumeroOrdenCompra,
            APTERM AS CodigoTerminos,
            APSTAT AS EstadoFactura,
            APPAYS AS BanderaSeleccionPago,
            PHHTRT AS TasaImpuestoMaxima,
            PHTXBA AS MontoImpuesto,
            APVNTX AS CodigoImpuestoProveedor,
            APPAYT AS TipoPago,
            HashDiff,
            FechaCargaInt
        FROM [int].factCompras
        WHERE @Reconciliar = 1 OR CONVERT(DATETIME2(3), FechaCargaInt) > @Desde
    ),
    OrigenConFk AS (
        SELECT o.*, e.EmpresaKey, p.ProveedorKey
        FROM Origen o
        LEFT JOIN dw.dimEmpresas e ON e.CodigoEmpresa = RIGHT('00' + CONVERT(VARCHAR(2), o.NumeroEmpresa), 2)
        LEFT JOIN dw.dimProveedor p ON p.CodigoProveedor = o.NumeroProveedor
    )
    SELECT * INTO #Origen FROM OrigenConFk;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM #Origen);

    MERGE dw.factCompras AS destino
        USING #Origen AS origen
        ON destino.NumeroEmpresa = origen.NumeroEmpresa AND destino.PrefijoDocumento = origen.PrefijoDocumento AND destino.AnioDocumento = origen.AnioDocumento AND destino.NumeroSecuenciaDocumento = origen.NumeroSecuenciaDocumento AND destino.NumeroLinea = origen.NumeroLinea
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff
                    OR (destino.EmpresaKey IS NULL AND origen.EmpresaKey IS NOT NULL) OR (destino.ProveedorKey IS NULL AND origen.ProveedorKey IS NOT NULL)) THEN
        UPDATE SET
            NumeroEmpresa = origen.NumeroEmpresa,
            PrefijoDocumento = origen.PrefijoDocumento,
            AnioDocumento = origen.AnioDocumento,
            NumeroSecuenciaDocumento = origen.NumeroSecuenciaDocumento,
            NumeroLinea = origen.NumeroLinea,
            NumeroProveedor = origen.NumeroProveedor,
            NumeroFacturaReferencia = origen.NumeroFacturaReferencia,
            TipoLinea = origen.TipoLinea,
            FechaContable = origen.FechaContable,
            MontoPago = origen.MontoPago,
            MontoPagoBase = origen.MontoPagoBase,
            DescripcionFactura = origen.DescripcionFactura,
            UsuarioCreacion = origen.UsuarioCreacion,
            FechaCreacion = origen.FechaCreacion,
            HoraCreacion = origen.HoraCreacion,
            CodigoRazon = origen.CodigoRazon,
            ProveedorPagoA = origen.ProveedorPagoA,
            CodigoBanco = origen.CodigoBanco,
            CodigoMoneda = origen.CodigoMoneda,
            FacturaEnRetencion = origen.FacturaEnRetencion,
            FechaFactura = origen.FechaFactura,
            FechaVencimiento = origen.FechaVencimiento,
            FechaDescuento = origen.FechaDescuento,
            MontoFacturaActual = origen.MontoFacturaActual,
            MontoPagadoActual = origen.MontoPagadoActual,
            SaldoPendiente = origen.SaldoPendiente,
            NumeroOrdenCompra = origen.NumeroOrdenCompra,
            CodigoTerminos = origen.CodigoTerminos,
            EstadoFactura = origen.EstadoFactura,
            BanderaSeleccionPago = origen.BanderaSeleccionPago,
            TasaImpuestoMaxima = origen.TasaImpuestoMaxima,
            MontoImpuesto = origen.MontoImpuesto,
            CodigoImpuestoProveedor = origen.CodigoImpuestoProveedor,
            TipoPago = origen.TipoPago,
            EmpresaKey   = origen.EmpresaKey,
            ProveedorKey = origen.ProveedorKey,
            HashDiff     = origen.HashDiff,
            FechaCargaDw = SYSDATETIME(),
            RunId        = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (EmpresaKey, ProveedorKey, NumeroEmpresa, PrefijoDocumento, AnioDocumento, NumeroSecuenciaDocumento, NumeroLinea, NumeroProveedor, NumeroFacturaReferencia, TipoLinea, FechaContable, MontoPago, MontoPagoBase, DescripcionFactura, UsuarioCreacion, FechaCreacion, HoraCreacion, CodigoRazon, ProveedorPagoA, CodigoBanco, CodigoMoneda, FacturaEnRetencion, FechaFactura, FechaVencimiento, FechaDescuento, MontoFacturaActual, MontoPagadoActual, SaldoPendiente, NumeroOrdenCompra, CodigoTerminos, EstadoFactura, BanderaSeleccionPago, TasaImpuestoMaxima, MontoImpuesto, CodigoImpuestoProveedor, TipoPago, HashDiff, RunId)
        VALUES (origen.EmpresaKey, origen.ProveedorKey, origen.NumeroEmpresa, origen.PrefijoDocumento, origen.AnioDocumento, origen.NumeroSecuenciaDocumento, origen.NumeroLinea, origen.NumeroProveedor, origen.NumeroFacturaReferencia, origen.TipoLinea, origen.FechaContable, origen.MontoPago, origen.MontoPagoBase, origen.DescripcionFactura, origen.UsuarioCreacion, origen.FechaCreacion, origen.HoraCreacion, origen.CodigoRazon, origen.ProveedorPagoA, origen.CodigoBanco, origen.CodigoMoneda, origen.FacturaEnRetencion, origen.FechaFactura, origen.FechaVencimiento, origen.FechaDescuento, origen.MontoFacturaActual, origen.MontoPagadoActual, origen.SaldoPendiente, origen.NumeroOrdenCompra, origen.CodigoTerminos, origen.EstadoFactura, origen.BanderaSeleccionPago, origen.TasaImpuestoMaxima, origen.MontoImpuesto, origen.CodigoImpuestoProveedor, origen.TipoPago, origen.HashDiff, @RunId)
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

-- Reinicio de los watermarks de gold (ver cabecera): la primera corrida
-- incremental compara todo una vez y desde ahi avanza por FechaCargaInt.
UPDATE w
SET UltimaCargaFechaHora = NULL,
    TipoCarga            = 'Incremental',
    FechaActualizacion   = SYSDATETIME()
FROM dbo.EtlWatermark w
JOIN dbo.EtlProcess p ON p.ProcesoId = w.ProcesoId
WHERE p.ProcesoNombre IN ('Envios_Gold', 'Ventas_Gold', 'Compras_Gold');

UPDATE dbo.EtlProcess SET TipoCarga = 'Incremental'
WHERE ProcesoNombre IN ('Envios_Gold', 'Ventas_Gold', 'Compras_Gold');
GO

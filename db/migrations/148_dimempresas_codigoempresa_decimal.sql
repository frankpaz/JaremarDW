-- 148: dw.dimEmpresas.CodigoEmpresa pasa de NVARCHAR(16) a DECIMAL(2,0), el mismo
-- tipo que CodigoEmpresa en dimCliente, dimProveedor, dimTerminosVenta,
-- factVentas y factCompras (decision del usuario). Verificado antes en dev y
-- prod: los 64 valores son numericos de 1-2 digitos y no hay duplicados al
-- convertir ('01' -> 1). Consecuencias:
--   * Los joins de gold de factVentas/factCompras ya no formatean con
--     RIGHT('00' + ...): comparan decimal con decimal (usa el indice unico).
--   * El SP de dimEmpresas convierte SVSGVL con CONVERT estricto: si el origen
--     trajera un codigo no numerico, la carga falla con error (y db/monitor_etl.py
--     avisa) en vez de descartarlo en silencio.
--   * Se pierde el cero a la izquierda al mostrarlo ('01' -> 1); si un reporte
--     lo necesita, se formatea en la consulta.
-- La UNIQUE sobre CodigoEmpresa se recrea porque ALTER COLUMN no puede correr con
-- ella activa. Silver ([int].dimEmpresas) conserva el texto del origen. Idempotente.

IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dw.dimEmpresas')
           AND name = 'CodigoEmpresa' AND TYPE_NAME(user_type_id) = 'nvarchar')
BEGIN
    ALTER TABLE dw.dimEmpresas DROP CONSTRAINT UQ_dw_dimEmpresas_CodigoEmpresa;
    ALTER TABLE dw.dimEmpresas ALTER COLUMN CodigoEmpresa DECIMAL(2,0) NOT NULL;
    ALTER TABLE dw.dimEmpresas ADD CONSTRAINT UQ_dw_dimEmpresas_CodigoEmpresa UNIQUE (CodigoEmpresa);
END
GO

CREATE OR ALTER PROCEDURE dw.usp_MergeDimEmpresas
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].dimEmpresas);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH Origen AS (
        SELECT
            CONVERT(DECIMAL(2,0), SVSGVL) AS CodigoEmpresa,
            SVID,
            SVLDES AS RazonSocial,
            SVDATE AS FechaRegistro,
            SVTIME AS HoraRegistro,
            MonedaFuncional AS CodigoMoneda,
            EsVigente,
            HashDiff
        FROM [int].dimEmpresas
    )
    MERGE dw.dimEmpresas AS destino
        USING Origen AS origen
        ON destino.CodigoEmpresa = origen.CodigoEmpresa
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente) THEN
        UPDATE SET
            SVID           = origen.SVID,
            RazonSocial    = origen.RazonSocial,
            FechaRegistro  = origen.FechaRegistro,
            HoraRegistro   = origen.HoraRegistro,
            CodigoMoneda   = origen.CodigoMoneda,
            EsVigente      = origen.EsVigente,
            HashDiff       = origen.HashDiff,
            FechaCargaDw   = SYSDATETIME(),
            RunId          = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (CodigoEmpresa, SVID, RazonSocial, FechaRegistro, HoraRegistro, CodigoMoneda, EsVigente, HashDiff, RunId)
        VALUES (origen.CodigoEmpresa, origen.SVID, origen.RazonSocial, origen.FechaRegistro, origen.HoraRegistro,
                origen.CodigoMoneda, origen.EsVigente, origen.HashDiff, @RunId)
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
            ILCOMP AS CodigoEmpresa,
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
            ILCUST AS CodigoCliente,
            ILCUSB AS CodigoClienteFacturacion,
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
        LEFT JOIN dw.dimEmpresas e ON e.CodigoEmpresa = o.CodigoEmpresa
        LEFT JOIN dw.dimProducto p ON p.CodigoProducto = o.CodigoProducto
    )
    SELECT * INTO #Origen FROM OrigenConFk;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM #Origen);

    MERGE dw.factVentas AS destino
        USING #Origen AS origen
        ON destino.CodigoEmpresa = origen.CodigoEmpresa AND destino.PrefijoDocumento = origen.PrefijoDocumento AND destino.NumeroDocumento = origen.NumeroDocumento AND destino.AnioDocumento = origen.AnioDocumento AND destino.TipoDocumento = origen.TipoDocumento AND destino.NumeroLinea = origen.NumeroLinea
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente
                    OR (destino.EmpresaKey IS NULL AND origen.EmpresaKey IS NOT NULL) OR (destino.ProductoKey IS NULL AND origen.ProductoKey IS NOT NULL)) THEN
        UPDATE SET
            CodigoEmpresa = origen.CodigoEmpresa,
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
            CodigoCliente = origen.CodigoCliente,
            CodigoClienteFacturacion = origen.CodigoClienteFacturacion,
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
        INSERT (EmpresaKey, ProductoKey, CodigoEmpresa, PrefijoDocumento, NumeroDocumento, AnioDocumento, TipoDocumento, NumeroLinea, NumeroSecuencia, NumeroDocumentoOriginal, NumeroOrden, FechaUltimaTransaccion, FechaEnvio, CodigoProducto, CodigoCliente, CodigoClienteFacturacion, Bodega, TipoLinea, ClaseOrden, Cantidad, CantidadUMVenta, PrecioNetoStocking, PrecioNetoVenta, PrecioListaTransaccion, PrecioListaBase, MontoExtendido, MontoIngreso, ILPCST, UnidadMedida, UnidadMedidaVentaOriginal, UnidadMedidaPesoCatch, CodigoImpuesto1, MontoImpuesto1, CodigoImpuesto2, MontoImpuesto2, Vendedor1, Vendedor3, CodigoComisionCliente, OrdenCompraCliente, NumeroConsolidacion, CodigoFuentePrecioNeto, CodigoFuentePrecioLista, InstalacionPrecio, GrupoEmpaque, CodigoMoneda, TasaCambioMoneda, TasaCambioGlobal, CodigoTerminos, Transportista, Ruta, FechaCreacion, HoraCreacion, UsuarioCreacion, EsVigente, HashDiff, RunId)
        VALUES (origen.EmpresaKey, origen.ProductoKey, origen.CodigoEmpresa, origen.PrefijoDocumento, origen.NumeroDocumento, origen.AnioDocumento, origen.TipoDocumento, origen.NumeroLinea, origen.NumeroSecuencia, origen.NumeroDocumentoOriginal, origen.NumeroOrden, origen.FechaUltimaTransaccion, origen.FechaEnvio, origen.CodigoProducto, origen.CodigoCliente, origen.CodigoClienteFacturacion, origen.Bodega, origen.TipoLinea, origen.ClaseOrden, origen.Cantidad, origen.CantidadUMVenta, origen.PrecioNetoStocking, origen.PrecioNetoVenta, origen.PrecioListaTransaccion, origen.PrecioListaBase, origen.MontoExtendido, origen.MontoIngreso, origen.ILPCST, origen.UnidadMedida, origen.UnidadMedidaVentaOriginal, origen.UnidadMedidaPesoCatch, origen.CodigoImpuesto1, origen.MontoImpuesto1, origen.CodigoImpuesto2, origen.MontoImpuesto2, origen.Vendedor1, origen.Vendedor3, origen.CodigoComisionCliente, origen.OrdenCompraCliente, origen.NumeroConsolidacion, origen.CodigoFuentePrecioNeto, origen.CodigoFuentePrecioLista, origen.InstalacionPrecio, origen.GrupoEmpaque, origen.CodigoMoneda, origen.TasaCambioMoneda, origen.TasaCambioGlobal, origen.CodigoTerminos, origen.Transportista, origen.Ruta, origen.FechaCreacion, origen.HoraCreacion, origen.UsuarioCreacion, origen.EsVigente, origen.HashDiff, @RunId)
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
            PLCMPY AS CodigoEmpresa,
            PLDCPX AS PrefijoDocumento,
            PLDCYR AS AnioDocumento,
            PLDCSQ AS NumeroSecuenciaDocumento,
            PLLINE AS NumeroLinea,
            PLVNDR AS CodigoProveedor,
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
        LEFT JOIN dw.dimEmpresas e ON e.CodigoEmpresa = o.CodigoEmpresa
        LEFT JOIN dw.dimProveedor p ON p.CodigoProveedor = o.CodigoProveedor
    )
    SELECT * INTO #Origen FROM OrigenConFk;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM #Origen);

    MERGE dw.factCompras AS destino
        USING #Origen AS origen
        ON destino.CodigoEmpresa = origen.CodigoEmpresa AND destino.PrefijoDocumento = origen.PrefijoDocumento AND destino.AnioDocumento = origen.AnioDocumento AND destino.NumeroSecuenciaDocumento = origen.NumeroSecuenciaDocumento AND destino.NumeroLinea = origen.NumeroLinea
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff
                    OR (destino.EmpresaKey IS NULL AND origen.EmpresaKey IS NOT NULL) OR (destino.ProveedorKey IS NULL AND origen.ProveedorKey IS NOT NULL)) THEN
        UPDATE SET
            CodigoEmpresa = origen.CodigoEmpresa,
            PrefijoDocumento = origen.PrefijoDocumento,
            AnioDocumento = origen.AnioDocumento,
            NumeroSecuenciaDocumento = origen.NumeroSecuenciaDocumento,
            NumeroLinea = origen.NumeroLinea,
            CodigoProveedor = origen.CodigoProveedor,
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
        INSERT (EmpresaKey, ProveedorKey, CodigoEmpresa, PrefijoDocumento, AnioDocumento, NumeroSecuenciaDocumento, NumeroLinea, CodigoProveedor, NumeroFacturaReferencia, TipoLinea, FechaContable, MontoPago, MontoPagoBase, DescripcionFactura, UsuarioCreacion, FechaCreacion, HoraCreacion, CodigoRazon, ProveedorPagoA, CodigoBanco, CodigoMoneda, FacturaEnRetencion, FechaFactura, FechaVencimiento, FechaDescuento, MontoFacturaActual, MontoPagadoActual, SaldoPendiente, NumeroOrdenCompra, CodigoTerminos, EstadoFactura, BanderaSeleccionPago, TasaImpuestoMaxima, MontoImpuesto, CodigoImpuestoProveedor, TipoPago, HashDiff, RunId)
        VALUES (origen.EmpresaKey, origen.ProveedorKey, origen.CodigoEmpresa, origen.PrefijoDocumento, origen.AnioDocumento, origen.NumeroSecuenciaDocumento, origen.NumeroLinea, origen.CodigoProveedor, origen.NumeroFacturaReferencia, origen.TipoLinea, origen.FechaContable, origen.MontoPago, origen.MontoPagoBase, origen.DescripcionFactura, origen.UsuarioCreacion, origen.FechaCreacion, origen.HoraCreacion, origen.CodigoRazon, origen.ProveedorPagoA, origen.CodigoBanco, origen.CodigoMoneda, origen.FacturaEnRetencion, origen.FechaFactura, origen.FechaVencimiento, origen.FechaDescuento, origen.MontoFacturaActual, origen.MontoPagadoActual, origen.SaldoPendiente, origen.NumeroOrdenCompra, origen.CodigoTerminos, origen.EstadoFactura, origen.BanderaSeleccionPago, origen.TasaImpuestoMaxima, origen.MontoImpuesto, origen.CodigoImpuestoProveedor, origen.TipoPago, origen.HashDiff, @RunId)
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

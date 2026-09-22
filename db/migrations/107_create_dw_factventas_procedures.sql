-- 107: merge Silver -> Gold para factVentas. SCD Tipo 1 (sobrescribe).
-- Reutiliza el HashDiff ya calculado en [int].factVentas. Resuelve
-- EmpresaKey (via NumeroEmpresa formateado a 2 digitos = CodigoEmpresa) y
-- ProductoKey (via CodigoProducto) con LEFT JOIN.

CREATE OR ALTER PROCEDURE dw.usp_MergeFactVentas
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].factVentas);

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
            HashDiff
        FROM [int].factVentas
    ),
    OrigenConFk AS (
        SELECT o.*, e.EmpresaKey, p.ProductoKey
        FROM Origen o
        LEFT JOIN dw.dimEmpresas e ON e.CodigoEmpresa = RIGHT('00' + CONVERT(VARCHAR(2), o.NumeroEmpresa), 2)
        LEFT JOIN dw.dimProducto p ON p.CodigoProducto = o.CodigoProducto
    )
    MERGE dw.factVentas AS destino
        USING OrigenConFk AS origen
        ON destino.NumeroEmpresa = origen.NumeroEmpresa AND destino.PrefijoDocumento = origen.PrefijoDocumento AND destino.NumeroDocumento = origen.NumeroDocumento AND destino.AnioDocumento = origen.AnioDocumento AND destino.TipoDocumento = origen.TipoDocumento AND destino.NumeroLinea = origen.NumeroLinea
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente) THEN
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

    SELECT
        @FilasLeidas                                                                 AS FilasLeidas,
        ISNULL(SUM(CASE WHEN Accion = 'INSERT' THEN 1 ELSE 0 END), 0)                AS FilasInsertadas,
        ISNULL(SUM(CASE WHEN Accion = 'UPDATE' THEN 1 ELSE 0 END), 0)                AS FilasActualizadas,
        @FilasLeidas - ISNULL(SUM(CASE WHEN Accion = 'INSERT' THEN 1 ELSE 0 END), 0)
                      - ISNULL(SUM(CASE WHEN Accion = 'UPDATE' THEN 1 ELSE 0 END), 0) AS FilasIgnoradas
    FROM #AccionesMerge;
END
GO

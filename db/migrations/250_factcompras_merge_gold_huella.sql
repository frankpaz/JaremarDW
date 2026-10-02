-- 250: gold de factCompras con la llave de la 248 (documento + linea + proveedor + factura +
-- fecha de creacion) y EsVigente. Parte de la version vigente (148: incremental por FechaCargaInt, reconciliacion,
-- relleno de EmpresaKey/ProveedorKey tardias) y solo cambia:
--   * el MERGE cruza tambien por CodigoProveedor, NumeroFacturaReferencia y FechaCreacion (las
--     ~428 lineas de secuencia 0 y las 91 recapturadas otro dia ahora son filas distintas en [int]);
--   * EsVigente viaja desde [int]: una linea dada de baja en silver queda con EsVigente = 0 aqui.
--     Los reportes deben filtrar EsVigente = 1.
-- Compatible con SQL Server 2016.

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
            EsVigente,
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
       AND ISNULL(destino.CodigoProveedor, -1) = ISNULL(origen.CodigoProveedor, -1) AND ISNULL(destino.NumeroFacturaReferencia, N'') = ISNULL(origen.NumeroFacturaReferencia, N'')
       AND ISNULL(destino.FechaCreacion, '19000101') = ISNULL(origen.FechaCreacion, '19000101')
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente
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
            EsVigente = origen.EsVigente,
            EmpresaKey   = origen.EmpresaKey,
            ProveedorKey = origen.ProveedorKey,
            HashDiff     = origen.HashDiff,
            FechaCargaDw = SYSDATETIME(),
            RunId        = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (EmpresaKey, ProveedorKey, CodigoEmpresa, PrefijoDocumento, AnioDocumento, NumeroSecuenciaDocumento, NumeroLinea, CodigoProveedor, NumeroFacturaReferencia, TipoLinea, FechaContable, MontoPago, MontoPagoBase, DescripcionFactura, UsuarioCreacion, FechaCreacion, HoraCreacion, CodigoRazon, ProveedorPagoA, CodigoBanco, CodigoMoneda, FacturaEnRetencion, FechaFactura, FechaVencimiento, FechaDescuento, MontoFacturaActual, MontoPagadoActual, SaldoPendiente, NumeroOrdenCompra, CodigoTerminos, EstadoFactura, BanderaSeleccionPago, TasaImpuestoMaxima, MontoImpuesto, CodigoImpuestoProveedor, TipoPago, EsVigente, HashDiff, RunId)
        VALUES (origen.EmpresaKey, origen.ProveedorKey, origen.CodigoEmpresa, origen.PrefijoDocumento, origen.AnioDocumento, origen.NumeroSecuenciaDocumento, origen.NumeroLinea, origen.CodigoProveedor, origen.NumeroFacturaReferencia, origen.TipoLinea, origen.FechaContable, origen.MontoPago, origen.MontoPagoBase, origen.DescripcionFactura, origen.UsuarioCreacion, origen.FechaCreacion, origen.HoraCreacion, origen.CodigoRazon, origen.ProveedorPagoA, origen.CodigoBanco, origen.CodigoMoneda, origen.FacturaEnRetencion, origen.FechaFactura, origen.FechaVencimiento, origen.FechaDescuento, origen.MontoFacturaActual, origen.MontoPagadoActual, origen.SaldoPendiente, origen.NumeroOrdenCompra, origen.CodigoTerminos, origen.EstadoFactura, origen.BanderaSeleccionPago, origen.TasaImpuestoMaxima, origen.MontoImpuesto, origen.CodigoImpuestoProveedor, origen.TipoPago, origen.EsVigente, origen.HashDiff, @RunId)
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

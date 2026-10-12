-- 269: AlmacenKey (dw.dimAlmacen) en dw.factVentas, dw.factManifiestos y dw.dimCliente.
-- Resuelve el codigo de almacen de cada uno contra dw.dimAlmacen.CodigoAlmacen:
--   factVentas.Bodega (ILWHS), factManifiestos.CodigoAlmacen (D02ALM) y
--   dimCliente.BodegaDefecto (CWHSE). Verificado en produccion (2026-10-12): los tres
--   cruzan al 100 %; en dimCliente 2.273 clientes no tienen bodega (AlmacenKey NULL) y
--   3.113 apuntan a almacenes dados de baja (EsActivo = 0 en la dimension).
--
-- Llegada tardia de un almacen (igual que las demas llaves de cada tabla):
--   factVentas      -> se completa cuando la fila vuelve a gold; la reconciliacion diaria
--                      (--reconciliar) recorre todo [int].
--   factManifiestos -> gold reemplaza su ventana; la reconciliacion semanal todo el historico.
--   dimCliente      -> carga FULL: se actualiza en cada corrida si la llave cambia.
-- Esta migracion NO rellena las filas que ya existen (son ~4,6 M y migrate.py aplica todo
-- en una transaccion): el relleno inicial se hace en lotes aparte (2026-10-12). En un
-- ambiente nuevo lo hacen la reconciliacion de ventas y de manifiestos y la siguiente
-- corrida de dimCliente.
-- Correr dimAlmacen antes que dimCliente (run_dimensiones.py). Compatible con SQL Server 2016.

IF COL_LENGTH('dw.factVentas', 'AlmacenKey') IS NULL
    ALTER TABLE dw.factVentas ADD AlmacenKey INT NULL
        CONSTRAINT FK_dw_factVentas_dimAlmacen REFERENCES dw.dimAlmacen(AlmacenKey);
GO

IF COL_LENGTH('dw.factManifiestos', 'AlmacenKey') IS NULL
    ALTER TABLE dw.factManifiestos ADD AlmacenKey INT NULL
        CONSTRAINT FK_dw_factManifiestos_dimAlmacen REFERENCES dw.dimAlmacen(AlmacenKey);
GO

IF COL_LENGTH('dw.dimCliente', 'AlmacenKey') IS NULL
    ALTER TABLE dw.dimCliente ADD AlmacenKey INT NULL
        CONSTRAINT FK_dw_dimCliente_dimAlmacen REFERENCES dw.dimAlmacen(AlmacenKey);
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
        SELECT o.*, e.EmpresaKey, p.ProductoKey, a.AlmacenKey
        FROM Origen o
        LEFT JOIN dw.dimEmpresas e ON e.CodigoEmpresa = o.CodigoEmpresa
        LEFT JOIN dw.dimProducto p ON p.CodigoProducto = o.CodigoProducto
        LEFT JOIN dw.dimAlmacen a  ON a.CodigoAlmacen = o.Bodega
    )
    SELECT * INTO #Origen FROM OrigenConFk;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM #Origen);

    MERGE dw.factVentas AS destino
        USING #Origen AS origen
        ON destino.CodigoEmpresa = origen.CodigoEmpresa AND destino.PrefijoDocumento = origen.PrefijoDocumento AND destino.NumeroDocumento = origen.NumeroDocumento AND destino.AnioDocumento = origen.AnioDocumento AND destino.TipoDocumento = origen.TipoDocumento AND destino.NumeroLinea = origen.NumeroLinea
       AND destino.FechaUltimaTransaccion = origen.FechaUltimaTransaccion
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente
                    OR (destino.EmpresaKey IS NULL AND origen.EmpresaKey IS NOT NULL) OR (destino.ProductoKey IS NULL AND origen.ProductoKey IS NOT NULL)
                    OR (destino.AlmacenKey IS NULL AND origen.AlmacenKey IS NOT NULL)) THEN
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
            AlmacenKey   = origen.AlmacenKey,
            EsVigente    = origen.EsVigente,
            HashDiff     = origen.HashDiff,
            FechaCargaDw = SYSDATETIME(),
            RunId        = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (EmpresaKey, ProductoKey, AlmacenKey, CodigoEmpresa, PrefijoDocumento, NumeroDocumento, AnioDocumento, TipoDocumento, NumeroLinea, NumeroSecuencia, NumeroDocumentoOriginal, NumeroOrden, FechaUltimaTransaccion, FechaEnvio, CodigoProducto, CodigoCliente, CodigoClienteFacturacion, Bodega, TipoLinea, ClaseOrden, Cantidad, CantidadUMVenta, PrecioNetoStocking, PrecioNetoVenta, PrecioListaTransaccion, PrecioListaBase, MontoExtendido, MontoIngreso, ILPCST, UnidadMedida, UnidadMedidaVentaOriginal, UnidadMedidaPesoCatch, CodigoImpuesto1, MontoImpuesto1, CodigoImpuesto2, MontoImpuesto2, Vendedor1, Vendedor3, CodigoComisionCliente, OrdenCompraCliente, NumeroConsolidacion, CodigoFuentePrecioNeto, CodigoFuentePrecioLista, InstalacionPrecio, GrupoEmpaque, CodigoMoneda, TasaCambioMoneda, TasaCambioGlobal, CodigoTerminos, Transportista, Ruta, FechaCreacion, HoraCreacion, UsuarioCreacion, EsVigente, HashDiff, RunId)
        VALUES (origen.EmpresaKey, origen.ProductoKey, origen.AlmacenKey, origen.CodigoEmpresa, origen.PrefijoDocumento, origen.NumeroDocumento, origen.AnioDocumento, origen.TipoDocumento, origen.NumeroLinea, origen.NumeroSecuencia, origen.NumeroDocumentoOriginal, origen.NumeroOrden, origen.FechaUltimaTransaccion, origen.FechaEnvio, origen.CodigoProducto, origen.CodigoCliente, origen.CodigoClienteFacturacion, origen.Bodega, origen.TipoLinea, origen.ClaseOrden, origen.Cantidad, origen.CantidadUMVenta, origen.PrecioNetoStocking, origen.PrecioNetoVenta, origen.PrecioListaTransaccion, origen.PrecioListaBase, origen.MontoExtendido, origen.MontoIngreso, origen.ILPCST, origen.UnidadMedida, origen.UnidadMedidaVentaOriginal, origen.UnidadMedidaPesoCatch, origen.CodigoImpuesto1, origen.MontoImpuesto1, origen.CodigoImpuesto2, origen.MontoImpuesto2, origen.Vendedor1, origen.Vendedor3, origen.CodigoComisionCliente, origen.OrdenCompraCliente, origen.NumeroConsolidacion, origen.CodigoFuentePrecioNeto, origen.CodigoFuentePrecioLista, origen.InstalacionPrecio, origen.GrupoEmpaque, origen.CodigoMoneda, origen.TasaCambioMoneda, origen.TasaCambioGlobal, origen.CodigoTerminos, origen.Transportista, origen.Ruta, origen.FechaCreacion, origen.HoraCreacion, origen.UsuarioCreacion, origen.EsVigente, origen.HashDiff, @RunId)
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

CREATE OR ALTER PROCEDURE dw.usp_MergeFactManifiestos
    @RunId            INT,
    @UltimoWatermark  DATETIME2(7) = NULL,
    @Reconciliar      BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @NuevoWatermark DATETIME2(7) = (SELECT MAX(FechaCargaInt) FROM [int].factManifiestos);
    DECLARE @Desde DATE;

    IF @Reconciliar = 1 OR @UltimoWatermark IS NULL
        SET @Desde = (SELECT MIN(D02FEC) FROM [int].factManifiestos);
    ELSE
        SET @Desde = (SELECT MIN(D02FEC) FROM [int].factManifiestos
                      WHERE FechaCargaInt >= DATEADD(MICROSECOND, 1, @UltimoWatermark));

    IF @Desde IS NULL
    BEGIN
        SELECT 0 AS FilasLeidas, 0 AS FilasInsertadas, 0 AS FilasActualizadas, 0 AS FilasIgnoradas,
               COALESCE(@NuevoWatermark, @UltimoWatermark) AS NuevoWatermark, 0 AS FilasEliminadas, CAST(NULL AS DATE) AS Desde;
        RETURN;
    END

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].factManifiestos WHERE D02FEC >= @Desde);

    DECLARE @FilasEliminadas INT;
    IF NOT EXISTS (SELECT 1 FROM dw.factManifiestos WHERE FechaCreacion < @Desde)
    BEGIN
        SET @FilasEliminadas = (SELECT COUNT(*) FROM dw.factManifiestos);
        TRUNCATE TABLE dw.factManifiestos;
    END
    ELSE
    BEGIN
        DELETE FROM dw.factManifiestos WHERE FechaCreacion >= @Desde;
        SET @FilasEliminadas = @@ROWCOUNT;
    END

    INSERT INTO dw.factManifiestos (
        EmpresaKey, ClienteKey, ProductoKey, RutaKey, AlmacenKey,
        CodigoEmpresa, NumeroOrden, CodigoCliente, NumeroLinea, CodigoProducto, Cantidad, Peso,
        CodigoAlmacen, CodigoLocalidad, UnidadMedida, NumeroReferencia, NumeroConsolidacion,
        CodigoRuta, CodigoRuta1, CodigoRuta2, MarcaProceso, FechaCreacion, HoraCreacion, RunId)
    SELECT
        e.EmpresaKey, c.ClienteKey, p.ProductoKey, r.RutaKey, a.AlmacenKey,
        i.D02CIA, i.D02ORD, i.D02CLI, i.D02LIN, i.D02PRO, i.D02CAN, i.D02PES,
        i.D02ALM, i.D02LOC, i.D02UM, i.D02REF, i.D02CON,
        i.D02DSR, i.D02DSS, i.D02DST, i.D02MAR, i.D02FEC, i.D02HOR, @RunId
    FROM [int].factManifiestos i
    LEFT JOIN dw.dimEmpresas e ON e.CodigoEmpresa  = i.D02CIA
    LEFT JOIN dw.dimCliente  c ON c.CodigoCliente  = i.D02CLI
    LEFT JOIN dw.dimProducto p ON p.CodigoProducto = i.D02PRO
    LEFT JOIN dw.dimRuta     r ON r.CodigoRuta     = i.D02DSR
    LEFT JOIN dw.dimAlmacen  a ON a.CodigoAlmacen  = i.D02ALM
    WHERE i.D02FEC >= @Desde;
    DECLARE @FilasInsertadas INT = @@ROWCOUNT;

    SELECT
        @FilasLeidas                     AS FilasLeidas,
        @FilasInsertadas                 AS FilasInsertadas,
        0                                AS FilasActualizadas,
        @FilasLeidas - @FilasInsertadas  AS FilasIgnoradas,
        @NuevoWatermark                  AS NuevoWatermark,
        @FilasEliminadas                 AS FilasEliminadas,
        @Desde                           AS Desde;
END
GO

CREATE OR ALTER PROCEDURE dw.usp_MergeDimCliente
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].dimCliente);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH Origen AS (
        SELECT
            CCUST   AS CodigoCliente,
            CAST(CASE WHEN CMID = 'CM' THEN 1 ELSE 0 END AS BIT) AS EsActivo,
            CNME    AS NombreCliente,
            CMALPH  AS ClaveBusqueda,
            CAD1    AS Direccion1,
            CAD2    AS Direccion2,
            CAD3    AS Direccion3,
            CSTE    AS CodigoEstado,
            CZIP    AS CodigoPostal,
            CCOUN   AS CodigoPais,
            CTYPE   AS TipoCliente,
            CCOMP   AS CodigoEmpresa,
            CCCUS   AS NumeroClienteCorporativo,
            CREG    AS RegionPromocion,
            CMPREG  AS RegionPrecio,
            CDEA1   AS CodigoGrupo1,
            CSAL    AS Vendedor,
            CTERM   AS CodigoTerminos,
            CTAX    AS CodigoImpuesto,
            CTXID   AS NumeroIdentificacionFiscal,
            CPCD    AS CodigoPago,
            CCURR   AS CodigoMoneda,
            CWHSE   AS BodegaDefecto,
            (SELECT a.AlmacenKey FROM dw.dimAlmacen a WHERE a.CodigoAlmacen = CWHSE) AS AlmacenKey,
            CROUT   AS Ruta,
            CMDFOT  AS TipoOrdenDefecto,
            CCON    AS NombreContacto,
            CPHON   AS Telefono,
            CRDOL   AS LimiteCredito,
            CDLIM   AS DiasLimiteCredito,
            CAPD    AS PromedioDiasPago,
            CAIS    AS PromedioFactura,
            CLAST   AS FechaUltimaTransaccion,
            CLPDT   AS FechaUltimoPago,
            CLPAM   AS MontoUltimoPago,
            CMHOLD  AS CodigoRetencion,
            CMDCRT  AS FechaCreacion,
            CMENDT  AS FechaEntradaSistema,
            CMENTM  AS HoraEntradaSistema,
            CMENUS  AS UsuarioEntradaSistema,
            CLDTE   AS FechaUltimaModificacion,
            CLTME   AS HoraUltimaModificacion,
            CLUSR   AS UsuarioUltimaModificacion,
            EsVigente,
            HashDiff
        FROM [int].dimCliente
    )
    MERGE dw.dimCliente AS destino
        USING Origen AS origen
        ON destino.CodigoCliente = origen.CodigoCliente
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente
                      OR ISNULL(destino.AlmacenKey, -1) <> ISNULL(origen.AlmacenKey, -1)) THEN
        UPDATE SET
            EsActivo                   = origen.EsActivo,
            NombreCliente              = origen.NombreCliente,
            ClaveBusqueda              = origen.ClaveBusqueda,
            Direccion1                 = origen.Direccion1,
            Direccion2                 = origen.Direccion2,
            Direccion3                 = origen.Direccion3,
            CodigoEstado               = origen.CodigoEstado,
            CodigoPostal               = origen.CodigoPostal,
            CodigoPais                 = origen.CodigoPais,
            TipoCliente                = origen.TipoCliente,
            CodigoEmpresa              = origen.CodigoEmpresa,
            NumeroClienteCorporativo   = origen.NumeroClienteCorporativo,
            RegionPromocion            = origen.RegionPromocion,
            RegionPrecio               = origen.RegionPrecio,
            CodigoGrupo1               = origen.CodigoGrupo1,
            Vendedor                   = origen.Vendedor,
            CodigoTerminos             = origen.CodigoTerminos,
            CodigoImpuesto             = origen.CodigoImpuesto,
            NumeroIdentificacionFiscal = origen.NumeroIdentificacionFiscal,
            CodigoPago                 = origen.CodigoPago,
            CodigoMoneda               = origen.CodigoMoneda,
            BodegaDefecto              = origen.BodegaDefecto,
            AlmacenKey                 = origen.AlmacenKey,
            Ruta                       = origen.Ruta,
            TipoOrdenDefecto           = origen.TipoOrdenDefecto,
            NombreContacto             = origen.NombreContacto,
            Telefono                   = origen.Telefono,
            LimiteCredito              = origen.LimiteCredito,
            DiasLimiteCredito          = origen.DiasLimiteCredito,
            PromedioDiasPago           = origen.PromedioDiasPago,
            PromedioFactura            = origen.PromedioFactura,
            FechaUltimaTransaccion     = origen.FechaUltimaTransaccion,
            FechaUltimoPago            = origen.FechaUltimoPago,
            MontoUltimoPago            = origen.MontoUltimoPago,
            CodigoRetencion            = origen.CodigoRetencion,
            FechaCreacion              = origen.FechaCreacion,
            FechaEntradaSistema        = origen.FechaEntradaSistema,
            HoraEntradaSistema         = origen.HoraEntradaSistema,
            UsuarioEntradaSistema      = origen.UsuarioEntradaSistema,
            FechaUltimaModificacion    = origen.FechaUltimaModificacion,
            HoraUltimaModificacion     = origen.HoraUltimaModificacion,
            UsuarioUltimaModificacion  = origen.UsuarioUltimaModificacion,
            EsVigente                  = origen.EsVigente,
            HashDiff                   = origen.HashDiff,
            FechaCargaDw               = SYSDATETIME(),
            RunId                      = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (
            CodigoCliente, EsActivo, NombreCliente, ClaveBusqueda, Direccion1, Direccion2, Direccion3,
            CodigoEstado, CodigoPostal, CodigoPais, TipoCliente, CodigoEmpresa, NumeroClienteCorporativo,
            RegionPromocion, RegionPrecio, CodigoGrupo1, Vendedor, CodigoTerminos, CodigoImpuesto,
            NumeroIdentificacionFiscal, CodigoPago, CodigoMoneda, BodegaDefecto, AlmacenKey, Ruta, TipoOrdenDefecto,
            NombreContacto, Telefono, LimiteCredito, DiasLimiteCredito, PromedioDiasPago, PromedioFactura,
            FechaUltimaTransaccion, FechaUltimoPago, MontoUltimoPago, CodigoRetencion,
            FechaCreacion, FechaEntradaSistema, HoraEntradaSistema, UsuarioEntradaSistema,
            FechaUltimaModificacion, HoraUltimaModificacion, UsuarioUltimaModificacion,
            EsVigente, HashDiff, RunId
        )
        VALUES (
            origen.CodigoCliente, origen.EsActivo, origen.NombreCliente, origen.ClaveBusqueda, origen.Direccion1, origen.Direccion2, origen.Direccion3,
            origen.CodigoEstado, origen.CodigoPostal, origen.CodigoPais, origen.TipoCliente, origen.CodigoEmpresa, origen.NumeroClienteCorporativo,
            origen.RegionPromocion, origen.RegionPrecio, origen.CodigoGrupo1, origen.Vendedor, origen.CodigoTerminos, origen.CodigoImpuesto,
            origen.NumeroIdentificacionFiscal, origen.CodigoPago, origen.CodigoMoneda, origen.BodegaDefecto, origen.AlmacenKey, origen.Ruta, origen.TipoOrdenDefecto,
            origen.NombreContacto, origen.Telefono, origen.LimiteCredito, origen.DiasLimiteCredito, origen.PromedioDiasPago, origen.PromedioFactura,
            origen.FechaUltimaTransaccion, origen.FechaUltimoPago, origen.MontoUltimoPago, origen.CodigoRetencion,
            origen.FechaCreacion, origen.FechaEntradaSistema, origen.HoraEntradaSistema, origen.UsuarioEntradaSistema,
            origen.FechaUltimaModificacion, origen.HoraUltimaModificacion, origen.UsuarioUltimaModificacion,
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
END
GO

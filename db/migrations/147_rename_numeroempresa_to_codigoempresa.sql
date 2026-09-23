-- 147: renombra NumeroEmpresa -> CodigoEmpresa en dw.dimCliente, dw.dimProveedor,
-- dw.dimTerminosVenta, dw.factVentas y dw.factCompras (decision del usuario,
-- para que el codigo de la empresa se llame igual en toda la capa dw, como
-- dw.dimEmpresas.CodigoEmpresa).
-- OJO: en estas 5 tablas es DECIMAL(2,0) (numero de compania del origen),
-- mientras que dw.dimEmpresas.CodigoEmpresa es NVARCHAR(16) ('01'); por eso los
-- joins de gold siguen convirtiendo con RIGHT('00' + CONVERT(VARCHAR(2), ...), 2).
-- Los indices y constraints (UQ_dw_factVentas_Linea, UQ_dw_factCompras_Linea,
-- UQ_dw_dimTerminosVenta_Codigo) se actualizan solos con sp_rename. Los SPs de
-- gold se recrean en esta misma migracion porque sp_rename no actualiza su
-- texto (solo estos 5 dependen de la columna; verificado en dev y prod).
-- Silver ([int]) conserva los nombres del origen. Idempotente.

IF COL_LENGTH('dw.dimCliente', 'NumeroEmpresa') IS NOT NULL AND COL_LENGTH('dw.dimCliente', 'CodigoEmpresa') IS NULL
    EXEC sp_rename 'dw.dimCliente.NumeroEmpresa', 'CodigoEmpresa', 'COLUMN';
IF COL_LENGTH('dw.dimProveedor', 'NumeroEmpresa') IS NOT NULL AND COL_LENGTH('dw.dimProveedor', 'CodigoEmpresa') IS NULL
    EXEC sp_rename 'dw.dimProveedor.NumeroEmpresa', 'CodigoEmpresa', 'COLUMN';
IF COL_LENGTH('dw.dimTerminosVenta', 'NumeroEmpresa') IS NOT NULL AND COL_LENGTH('dw.dimTerminosVenta', 'CodigoEmpresa') IS NULL
    EXEC sp_rename 'dw.dimTerminosVenta.NumeroEmpresa', 'CodigoEmpresa', 'COLUMN';
IF COL_LENGTH('dw.factVentas', 'NumeroEmpresa') IS NOT NULL AND COL_LENGTH('dw.factVentas', 'CodigoEmpresa') IS NULL
    EXEC sp_rename 'dw.factVentas.NumeroEmpresa', 'CodigoEmpresa', 'COLUMN';
IF COL_LENGTH('dw.factCompras', 'NumeroEmpresa') IS NOT NULL AND COL_LENGTH('dw.factCompras', 'CodigoEmpresa') IS NULL
    EXEC sp_rename 'dw.factCompras.NumeroEmpresa', 'CodigoEmpresa', 'COLUMN';
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
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente) THEN
        UPDATE SET
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
            CodigoCliente, NombreCliente, ClaveBusqueda, Direccion1, Direccion2, Direccion3,
            CodigoEstado, CodigoPostal, CodigoPais, TipoCliente, CodigoEmpresa, NumeroClienteCorporativo,
            RegionPromocion, RegionPrecio, CodigoGrupo1, Vendedor, CodigoTerminos, CodigoImpuesto,
            NumeroIdentificacionFiscal, CodigoPago, CodigoMoneda, BodegaDefecto, Ruta, TipoOrdenDefecto,
            NombreContacto, Telefono, LimiteCredito, DiasLimiteCredito, PromedioDiasPago, PromedioFactura,
            FechaUltimaTransaccion, FechaUltimoPago, MontoUltimoPago, CodigoRetencion,
            FechaCreacion, FechaEntradaSistema, HoraEntradaSistema, UsuarioEntradaSistema,
            FechaUltimaModificacion, HoraUltimaModificacion, UsuarioUltimaModificacion,
            EsVigente, HashDiff, RunId
        )
        VALUES (
            origen.CodigoCliente, origen.NombreCliente, origen.ClaveBusqueda, origen.Direccion1, origen.Direccion2, origen.Direccion3,
            origen.CodigoEstado, origen.CodigoPostal, origen.CodigoPais, origen.TipoCliente, origen.CodigoEmpresa, origen.NumeroClienteCorporativo,
            origen.RegionPromocion, origen.RegionPrecio, origen.CodigoGrupo1, origen.Vendedor, origen.CodigoTerminos, origen.CodigoImpuesto,
            origen.NumeroIdentificacionFiscal, origen.CodigoPago, origen.CodigoMoneda, origen.BodegaDefecto, origen.Ruta, origen.TipoOrdenDefecto,
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

CREATE OR ALTER PROCEDURE dw.usp_MergeDimProveedor
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].dimProveedor);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH Origen AS (
        SELECT
            VENDOR  AS CodigoProveedor,
            VNDNAM  AS NombreProveedor,
            VNALPH  AS ClaveBusqueda,
            VNDAD1  AS Direccion1,
            VNDAD2  AS Direccion2,
            VSTATE  AS CodigoEstado,
            VCOUN   AS CodigoPais,
            VTYPE   AS TipoProveedor,
            VCMPNY  AS CodigoEmpresa,
            VTERMS  AS CodigoTerminos,
            VPAYTO  AS ProveedorPagoA,
            VCURR   AS CodigoMoneda,
            VPAYTY  AS MetodoPago,
            V1TIME  AS ProveedorUnaVez,
            VCON    AS NombreContacto,
            VPHONE  AS Telefono,
            VTAX    AS CostoIncluyeImpuesto,
            VTAXCD  AS CodigoImpuesto,
            VMIDNM  AS NumeroIdentificacionFiscal,
            V1099   AS TipoProveedor1099,
            V1099C  AS Codigo1099,
            VDTLPD  AS FechaUltimoPago,
            VPYTYR  AS PagosAnioActual,
            VDPURS  AS ComprasAnioActual,
            VHOLD   AS CodigoRetencion,
            VNSTAT  AS EstadoProveedor,
            VMBANK  AS CodigoBanco,
            VMBNKC  AS CodigoBancoDetalle,
            VMBRNO  AS SucursalBancaria,
            VMBNKA  AS CuentaBancaria,
            VMCARR  AS Transportista,
            VMMNTR  AS MedioTransporte,
            VMLANG  AS Idioma,
            EsVigente,
            HashDiff
        FROM [int].dimProveedor
    )
    MERGE dw.dimProveedor AS destino
        USING Origen AS origen
        ON destino.CodigoProveedor = origen.CodigoProveedor
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente) THEN
        UPDATE SET
            NombreProveedor              = origen.NombreProveedor,
            ClaveBusqueda                = origen.ClaveBusqueda,
            Direccion1                   = origen.Direccion1,
            Direccion2                   = origen.Direccion2,
            CodigoEstado                 = origen.CodigoEstado,
            CodigoPais                   = origen.CodigoPais,
            TipoProveedor                = origen.TipoProveedor,
            CodigoEmpresa                = origen.CodigoEmpresa,
            CodigoTerminos               = origen.CodigoTerminos,
            ProveedorPagoA               = origen.ProveedorPagoA,
            CodigoMoneda                 = origen.CodigoMoneda,
            MetodoPago                   = origen.MetodoPago,
            ProveedorUnaVez              = origen.ProveedorUnaVez,
            NombreContacto               = origen.NombreContacto,
            Telefono                     = origen.Telefono,
            CostoIncluyeImpuesto         = origen.CostoIncluyeImpuesto,
            CodigoImpuesto               = origen.CodigoImpuesto,
            NumeroIdentificacionFiscal   = origen.NumeroIdentificacionFiscal,
            TipoProveedor1099            = origen.TipoProveedor1099,
            Codigo1099                   = origen.Codigo1099,
            FechaUltimoPago              = origen.FechaUltimoPago,
            PagosAnioActual              = origen.PagosAnioActual,
            ComprasAnioActual            = origen.ComprasAnioActual,
            CodigoRetencion              = origen.CodigoRetencion,
            EstadoProveedor              = origen.EstadoProveedor,
            CodigoBanco                  = origen.CodigoBanco,
            CodigoBancoDetalle           = origen.CodigoBancoDetalle,
            SucursalBancaria             = origen.SucursalBancaria,
            CuentaBancaria               = origen.CuentaBancaria,
            Transportista                = origen.Transportista,
            MedioTransporte              = origen.MedioTransporte,
            Idioma                       = origen.Idioma,
            EsVigente                    = origen.EsVigente,
            HashDiff                     = origen.HashDiff,
            FechaCargaDw                 = SYSDATETIME(),
            RunId                        = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (
            CodigoProveedor, NombreProveedor, ClaveBusqueda, Direccion1, Direccion2,
            CodigoEstado, CodigoPais, TipoProveedor, CodigoEmpresa, CodigoTerminos,
            ProveedorPagoA, CodigoMoneda, MetodoPago, ProveedorUnaVez, NombreContacto, Telefono,
            CostoIncluyeImpuesto, CodigoImpuesto, NumeroIdentificacionFiscal, TipoProveedor1099, Codigo1099,
            FechaUltimoPago, PagosAnioActual, ComprasAnioActual, CodigoRetencion, EstadoProveedor,
            CodigoBanco, CodigoBancoDetalle, SucursalBancaria, CuentaBancaria,
            Transportista, MedioTransporte, Idioma,
            EsVigente, HashDiff, RunId
        )
        VALUES (
            origen.CodigoProveedor, origen.NombreProveedor, origen.ClaveBusqueda, origen.Direccion1, origen.Direccion2,
            origen.CodigoEstado, origen.CodigoPais, origen.TipoProveedor, origen.CodigoEmpresa, origen.CodigoTerminos,
            origen.ProveedorPagoA, origen.CodigoMoneda, origen.MetodoPago, origen.ProveedorUnaVez, origen.NombreContacto, origen.Telefono,
            origen.CostoIncluyeImpuesto, origen.CodigoImpuesto, origen.NumeroIdentificacionFiscal, origen.TipoProveedor1099, origen.Codigo1099,
            origen.FechaUltimoPago, origen.PagosAnioActual, origen.ComprasAnioActual, origen.CodigoRetencion, origen.EstadoProveedor,
            origen.CodigoBanco, origen.CodigoBancoDetalle, origen.SucursalBancaria, origen.CuentaBancaria,
            origen.Transportista, origen.MedioTransporte, origen.Idioma,
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

CREATE OR ALTER PROCEDURE dw.usp_MergeDimTerminosVenta
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].dimTerminosVenta);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH Origen AS (
        SELECT
            TMCMPN AS CodigoEmpresa,
            TMTERM AS CodigoTerminos,
            TMDESC AS Descripcion,
            TMDUE  AS DiasVencimiento,
            TMTAXD AS ImpuestoAntesDescuento,
            TMBBTA AS ImpuestoSobreNetoDescuento,
            TMCWO  AS PagoContraOrden,
            EsVigente,
            HashDiff
        FROM [int].dimTerminosVenta
    )
    MERGE dw.dimTerminosVenta AS destino
        USING Origen AS origen
        ON destino.CodigoEmpresa = origen.CodigoEmpresa AND destino.CodigoTerminos = origen.CodigoTerminos
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente) THEN
        UPDATE SET
            Descripcion                = origen.Descripcion,
            DiasVencimiento            = origen.DiasVencimiento,
            ImpuestoAntesDescuento     = origen.ImpuestoAntesDescuento,
            ImpuestoSobreNetoDescuento = origen.ImpuestoSobreNetoDescuento,
            PagoContraOrden            = origen.PagoContraOrden,
            EsVigente                  = origen.EsVigente,
            HashDiff                   = origen.HashDiff,
            FechaCargaDw               = SYSDATETIME(),
            RunId                      = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (CodigoEmpresa, CodigoTerminos, Descripcion, DiasVencimiento, ImpuestoAntesDescuento, ImpuestoSobreNetoDescuento, PagoContraOrden, EsVigente, HashDiff, RunId)
        VALUES (origen.CodigoEmpresa, origen.CodigoTerminos, origen.Descripcion, origen.DiasVencimiento, origen.ImpuestoAntesDescuento, origen.ImpuestoSobreNetoDescuento, origen.PagoContraOrden, origen.EsVigente, origen.HashDiff, @RunId)
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
        LEFT JOIN dw.dimEmpresas e ON e.CodigoEmpresa = RIGHT('00' + CONVERT(VARCHAR(2), o.CodigoEmpresa), 2)
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
        LEFT JOIN dw.dimEmpresas e ON e.CodigoEmpresa = RIGHT('00' + CONVERT(VARCHAR(2), o.CodigoEmpresa), 2)
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

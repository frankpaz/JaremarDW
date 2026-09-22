-- 115: merge Silver -> Gold para dimProveedor. SCD Tipo 1 (sobrescribe).
-- Reutiliza el HashDiff ya calculado en [int].dimProveedor.

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
            VCMPNY  AS NumeroEmpresa,
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
            NumeroEmpresa                = origen.NumeroEmpresa,
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
            CodigoEstado, CodigoPais, TipoProveedor, NumeroEmpresa, CodigoTerminos,
            ProveedorPagoA, CodigoMoneda, MetodoPago, ProveedorUnaVez, NombreContacto, Telefono,
            CostoIncluyeImpuesto, CodigoImpuesto, NumeroIdentificacionFiscal, TipoProveedor1099, Codigo1099,
            FechaUltimoPago, PagosAnioActual, ComprasAnioActual, CodigoRetencion, EstadoProveedor,
            CodigoBanco, CodigoBancoDetalle, SucursalBancaria, CuentaBancaria,
            Transportista, MedioTransporte, Idioma,
            EsVigente, HashDiff, RunId
        )
        VALUES (
            origen.CodigoProveedor, origen.NombreProveedor, origen.ClaveBusqueda, origen.Direccion1, origen.Direccion2,
            origen.CodigoEstado, origen.CodigoPais, origen.TipoProveedor, origen.NumeroEmpresa, origen.CodigoTerminos,
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

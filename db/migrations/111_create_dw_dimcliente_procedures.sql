-- 111: merge Silver -> Gold para dimCliente. SCD Tipo 1 (sobrescribe).
-- Reutiliza el HashDiff ya calculado en [int].dimCliente.

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
            CCOMP   AS NumeroEmpresa,
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
            NumeroEmpresa              = origen.NumeroEmpresa,
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
            CodigoEstado, CodigoPostal, CodigoPais, TipoCliente, NumeroEmpresa, NumeroClienteCorporativo,
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
            origen.CodigoEstado, origen.CodigoPostal, origen.CodigoPais, origen.TipoCliente, origen.NumeroEmpresa, origen.NumeroClienteCorporativo,
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

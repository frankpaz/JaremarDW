-- 179: dimCliente incluye los clientes dados de baja (PROLX835F.RCM CMID='CZ').
-- Hasta aqui solo se cargaba CMID='CM' (activos, 33.760); los documentos emitidos a
-- clientes que despues pasaron a 'CZ' quedaban sin cliente (2.374 clientes / 7,2 % de
-- las filas de factGuiasRemision, 534 en factVentas; analisis 2026-09-28). CCUST sigue
-- siendo unico: 0 codigos repetidos entre CM y CZ.
--   [int].dimCliente.CMID  : 'CM' / 'CZ' tal cual el origen (entra al HashDiff).
--   dw.dimCliente.EsActivo : 1 = CM (activo), 0 = CZ (dado de baja). Los reportes que
--                            necesiten solo clientes activos deben filtrar EsActivo = 1.
-- EsVigente conserva su significado: 1 si el cliente existe en RCM (en CM o en CZ).
-- Los SPs se recrean a partir de los vigentes (109 para [int], 147 para dw) mas la columna
-- nueva. Idempotente. Compatible con SQL Server 2016.

-- stg tambien: el SP de [int] lee stg.dimCliente.CMID y SQL Server valida las columnas
-- de las tablas existentes al compilarlo. El extract no la recrea porque ya coincide
-- con sus columnas esperadas (CMID + las de siempre).
IF OBJECT_ID('stg.dimCliente') IS NOT NULL AND COL_LENGTH('stg.dimCliente', 'CMID') IS NULL
    ALTER TABLE stg.dimCliente ADD CMID NVARCHAR(2) NULL;
IF COL_LENGTH('int.dimCliente', 'CMID') IS NULL
    ALTER TABLE [int].dimCliente ADD CMID NVARCHAR(2) NULL;
IF COL_LENGTH('dw.dimCliente', 'EsActivo') IS NULL
    ALTER TABLE dw.dimCliente ADD EsActivo BIT NOT NULL CONSTRAINT DF_dw_dimCliente_EsActivo DEFAULT (1);
GO

CREATE OR ALTER PROCEDURE [int].usp_MergeDimCliente
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.dimCliente);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH StgDeduplicado AS (
        SELECT s.*,
               ROW_NUMBER() OVER (PARTITION BY s.CCUST ORDER BY s.CMENDT DESC, s.CMENTM DESC) AS rn
        FROM stg.dimCliente s
        WHERE s.CCUST IS NOT NULL
    ),
    StgNormalizado AS (
        SELECT
            s.CCUST                                                        AS CCUST,
            NULLIF(RTRIM(s.CMID), '')                                      AS CMID,
            NULLIF(RTRIM(s.CNME), '')                                      AS CNME,
            NULLIF(RTRIM(s.CMALPH), '')                                    AS CMALPH,
            NULLIF(RTRIM(s.CAD1), '')                                      AS CAD1,
            NULLIF(RTRIM(s.CAD2), '')                                      AS CAD2,
            NULLIF(RTRIM(s.CAD3), '')                                      AS CAD3,
            NULLIF(RTRIM(s.CSTE), '')                                      AS CSTE,
            NULLIF(RTRIM(s.CZIP), '')                                      AS CZIP,
            NULLIF(RTRIM(s.CCOUN), '')                                     AS CCOUN,
            NULLIF(RTRIM(s.CTYPE), '')                                     AS CTYPE,
            s.CCOMP                                                        AS CCOMP,
            s.CCCUS                                                        AS CCCUS,
            NULLIF(RTRIM(s.CREG), '')                                      AS CREG,
            NULLIF(RTRIM(s.CMPREG), '')                                    AS CMPREG,
            NULLIF(RTRIM(s.CDEA1), '')                                     AS CDEA1,
            s.CSAL                                                         AS CSAL,
            NULLIF(RTRIM(s.CTERM), '')                                     AS CTERM,
            NULLIF(RTRIM(s.CTAX), '')                                      AS CTAX,
            NULLIF(RTRIM(s.CTXID), '')                                     AS CTXID,
            NULLIF(RTRIM(s.CPCD), '')                                      AS CPCD,
            NULLIF(RTRIM(s.CCURR), '')                                     AS CCURR,
            NULLIF(RTRIM(s.CWHSE), '')                                     AS CWHSE,
            NULLIF(RTRIM(s.CROUT), '')                                     AS CROUT,
            NULLIF(RTRIM(s.CMDFOT), '')                                    AS CMDFOT,
            NULLIF(RTRIM(s.CCON), '')                                      AS CCON,
            NULLIF(RTRIM(s.CPHON), '')                                     AS CPHON,
            s.CRDOL                                                        AS CRDOL,
            s.CDLIM                                                        AS CDLIM,
            s.CAPD                                                         AS CAPD,
            s.CAIS                                                         AS CAIS,
            TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(s.CLAST AS BIGINT)))   AS CLAST,
            TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(s.CLPDT AS BIGINT)))   AS CLPDT,
            s.CLPAM                                                        AS CLPAM,
            NULLIF(RTRIM(s.CMHOLD), '')                                    AS CMHOLD,
            TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(s.CMDCRT AS BIGINT)))  AS CMDCRT,
            TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(s.CMENDT AS BIGINT)))  AS CMENDT,
            TRY_CONVERT(TIME(0), STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(6), CAST(s.CMENTM AS BIGINT)), 6), 3, 0, ':'), 6, 0, ':')) AS CMENTM,
            NULLIF(RTRIM(s.CMENUS), '')                                    AS CMENUS,
            TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(s.CLDTE AS BIGINT)))   AS CLDTE,
            TRY_CONVERT(TIME(0), STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(6), CAST(s.CLTME AS BIGINT)), 6), 3, 0, ':'), 6, 0, ':')) AS CLTME,
            NULLIF(RTRIM(s.CLUSR), '')                                     AS CLUSR
        FROM StgDeduplicado s
        WHERE s.rn = 1
    ),
    StgConHash AS (
        SELECT
            n.*,
            HASHBYTES('SHA2_256', (SELECT n.* FOR XML RAW, BINARY BASE64)) AS HashDiff
        FROM StgNormalizado n
    )
    MERGE [int].dimCliente AS destino
        USING StgConHash AS origen
        ON destino.CCUST = origen.CCUST
    WHEN MATCHED AND destino.HashDiff <> origen.HashDiff THEN
        UPDATE SET
            CMID          = origen.CMID,
            CNME          = origen.CNME,
            CMALPH        = origen.CMALPH,
            CAD1          = origen.CAD1,
            CAD2          = origen.CAD2,
            CAD3          = origen.CAD3,
            CSTE          = origen.CSTE,
            CZIP          = origen.CZIP,
            CCOUN         = origen.CCOUN,
            CTYPE         = origen.CTYPE,
            CCOMP         = origen.CCOMP,
            CCCUS         = origen.CCCUS,
            CREG          = origen.CREG,
            CMPREG        = origen.CMPREG,
            CDEA1         = origen.CDEA1,
            CSAL          = origen.CSAL,
            CTERM         = origen.CTERM,
            CTAX          = origen.CTAX,
            CTXID         = origen.CTXID,
            CPCD          = origen.CPCD,
            CCURR         = origen.CCURR,
            CWHSE         = origen.CWHSE,
            CROUT         = origen.CROUT,
            CMDFOT        = origen.CMDFOT,
            CCON          = origen.CCON,
            CPHON         = origen.CPHON,
            CRDOL         = origen.CRDOL,
            CDLIM         = origen.CDLIM,
            CAPD          = origen.CAPD,
            CAIS          = origen.CAIS,
            CLAST         = origen.CLAST,
            CLPDT         = origen.CLPDT,
            CLPAM         = origen.CLPAM,
            CMHOLD        = origen.CMHOLD,
            CMDCRT        = origen.CMDCRT,
            CMENDT        = origen.CMENDT,
            CMENTM        = origen.CMENTM,
            CMENUS        = origen.CMENUS,
            CLDTE         = origen.CLDTE,
            CLTME         = origen.CLTME,
            CLUSR         = origen.CLUSR,
            EsVigente     = 1,
            HashDiff      = origen.HashDiff,
            FechaCargaInt = SYSDATETIME(),
            RunId         = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (
            CCUST, CMID, CNME, CMALPH, CAD1, CAD2, CAD3, CSTE, CZIP, CCOUN, CTYPE,
            CCOMP, CCCUS, CREG, CMPREG, CDEA1, CSAL, CTERM, CTAX, CTXID, CPCD,
            CCURR, CWHSE, CROUT, CMDFOT, CCON, CPHON, CRDOL, CDLIM, CAPD, CAIS,
            CLAST, CLPDT, CLPAM, CMHOLD, CMDCRT, CMENDT, CMENTM, CMENUS,
            CLDTE, CLTME, CLUSR, HashDiff, RunId
        )
        VALUES (
            origen.CCUST, origen.CMID, origen.CNME, origen.CMALPH, origen.CAD1, origen.CAD2, origen.CAD3, origen.CSTE, origen.CZIP, origen.CCOUN, origen.CTYPE,
            origen.CCOMP, origen.CCCUS, origen.CREG, origen.CMPREG, origen.CDEA1, origen.CSAL, origen.CTERM, origen.CTAX, origen.CTXID, origen.CPCD,
            origen.CCURR, origen.CWHSE, origen.CROUT, origen.CMDFOT, origen.CCON, origen.CPHON, origen.CRDOL, origen.CDLIM, origen.CAPD, origen.CAIS,
            origen.CLAST, origen.CLPDT, origen.CLPAM, origen.CMHOLD, origen.CMDCRT, origen.CMENDT, origen.CMENTM, origen.CMENUS,
            origen.CLDTE, origen.CLTME, origen.CLUSR, origen.HashDiff, @RunId
        )
    WHEN NOT MATCHED BY SOURCE AND destino.EsVigente = 1 THEN
        UPDATE SET EsVigente = 0, FechaCargaInt = SYSDATETIME(), RunId = @RunId
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
            NumeroIdentificacionFiscal, CodigoPago, CodigoMoneda, BodegaDefecto, Ruta, TipoOrdenDefecto,
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

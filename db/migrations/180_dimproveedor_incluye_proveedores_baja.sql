-- 180: dimProveedor incluye los proveedores dados de baja (PROLX835F.AVM VMID='VZ'),
-- mismo criterio que dimCliente en la 179. Hasta aqui solo se cargaba VMID='VM' (activos,
-- 19.801); las compras a proveedores que despues pasaron a 'VZ' quedaban sin proveedor
-- (151 proveedores / 412 lineas de factCompras, casi todas 2019-2021; analisis 2026-09-28).
-- VENDOR sigue siendo unico: 0 codigos repetidos entre VM y VZ (5.649 en VZ).
--   [int].dimProveedor.VMID  : 'VM' / 'VZ' tal cual el origen (entra al HashDiff).
--   dw.dimProveedor.EsActivo : 1 = VM (activo), 0 = VZ (dado de baja). Los reportes que
--                              necesiten solo proveedores activos deben filtrar EsActivo = 1.
-- EsVigente conserva su significado: 1 si el proveedor existe en AVM (en VM o en VZ).
-- Los SPs se recrean a partir de los vigentes (113 para [int], 147 para dw) mas la columna
-- nueva. stg tambien recibe VMID: el SP de [int] la lee y SQL Server valida las columnas
-- de las tablas existentes al compilarlo. Idempotente. Compatible con SQL Server 2016.

IF OBJECT_ID('stg.dimProveedor') IS NOT NULL AND COL_LENGTH('stg.dimProveedor', 'VMID') IS NULL
    ALTER TABLE stg.dimProveedor ADD VMID NVARCHAR(2) NULL;
IF COL_LENGTH('int.dimProveedor', 'VMID') IS NULL
    ALTER TABLE [int].dimProveedor ADD VMID NVARCHAR(2) NULL;
IF COL_LENGTH('dw.dimProveedor', 'EsActivo') IS NULL
    ALTER TABLE dw.dimProveedor ADD EsActivo BIT NOT NULL CONSTRAINT DF_dw_dimProveedor_EsActivo DEFAULT (1);
GO

CREATE OR ALTER PROCEDURE [int].usp_MergeDimProveedor
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.dimProveedor);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH StgDeduplicado AS (
        SELECT s.*,
               ROW_NUMBER() OVER (PARTITION BY s.VENDOR ORDER BY (SELECT NULL)) AS rn
        FROM stg.dimProveedor s
        WHERE s.VENDOR IS NOT NULL
    ),
    StgNormalizado AS (
        SELECT
            s.VENDOR                                                       AS VENDOR,
            NULLIF(RTRIM(s.VMID), '')                                      AS VMID,
            NULLIF(RTRIM(s.VNDNAM), '')                                    AS VNDNAM,
            NULLIF(RTRIM(s.VNALPH), '')                                    AS VNALPH,
            NULLIF(RTRIM(s.VNDAD1), '')                                    AS VNDAD1,
            NULLIF(RTRIM(s.VNDAD2), '')                                    AS VNDAD2,
            NULLIF(RTRIM(s.VSTATE), '')                                    AS VSTATE,
            NULLIF(RTRIM(s.VCOUN), '')                                     AS VCOUN,
            NULLIF(RTRIM(s.VTYPE), '')                                     AS VTYPE,
            s.VCMPNY                                                       AS VCMPNY,
            NULLIF(RTRIM(s.VTERMS), '')                                    AS VTERMS,
            s.VPAYTO                                                       AS VPAYTO,
            NULLIF(RTRIM(s.VCURR), '')                                     AS VCURR,
            NULLIF(RTRIM(s.VPAYTY), '')                                    AS VPAYTY,
            NULLIF(RTRIM(s.V1TIME), '')                                    AS V1TIME,
            NULLIF(RTRIM(s.VCON), '')                                      AS VCON,
            NULLIF(RTRIM(s.VPHONE), '')                                    AS VPHONE,
            NULLIF(RTRIM(s.VTAX), '')                                      AS VTAX,
            NULLIF(RTRIM(s.VTAXCD), '')                                    AS VTAXCD,
            NULLIF(RTRIM(s.VMIDNM), '')                                    AS VMIDNM,
            NULLIF(RTRIM(s.V1099), '')                                     AS V1099,
            NULLIF(RTRIM(s.V1099C), '')                                    AS V1099C,
            TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(s.VDTLPD AS BIGINT)))  AS VDTLPD,
            s.VPYTYR                                                       AS VPYTYR,
            s.VDPURS                                                       AS VDPURS,
            NULLIF(RTRIM(s.VHOLD), '')                                     AS VHOLD,
            NULLIF(RTRIM(s.VNSTAT), '')                                    AS VNSTAT,
            NULLIF(RTRIM(s.VMBANK), '')                                    AS VMBANK,
            NULLIF(RTRIM(s.VMBNKC), '')                                    AS VMBNKC,
            NULLIF(RTRIM(s.VMBRNO), '')                                    AS VMBRNO,
            NULLIF(RTRIM(s.VMBNKA), '')                                    AS VMBNKA,
            NULLIF(RTRIM(s.VMCARR), '')                                    AS VMCARR,
            NULLIF(RTRIM(s.VMMNTR), '')                                    AS VMMNTR,
            NULLIF(RTRIM(s.VMLANG), '')                                    AS VMLANG
        FROM StgDeduplicado s
        WHERE s.rn = 1
    ),
    StgConHash AS (
        SELECT
            n.*,
            HASHBYTES('SHA2_256', (SELECT n.* FOR XML RAW, BINARY BASE64)) AS HashDiff
        FROM StgNormalizado n
    )
    MERGE [int].dimProveedor AS destino
        USING StgConHash AS origen
        ON destino.VENDOR = origen.VENDOR
    WHEN MATCHED AND destino.HashDiff <> origen.HashDiff THEN
        UPDATE SET
            VMID          = origen.VMID,
            VNDNAM        = origen.VNDNAM,
            VNALPH        = origen.VNALPH,
            VNDAD1        = origen.VNDAD1,
            VNDAD2        = origen.VNDAD2,
            VSTATE        = origen.VSTATE,
            VCOUN         = origen.VCOUN,
            VTYPE         = origen.VTYPE,
            VCMPNY        = origen.VCMPNY,
            VTERMS        = origen.VTERMS,
            VPAYTO        = origen.VPAYTO,
            VCURR         = origen.VCURR,
            VPAYTY        = origen.VPAYTY,
            V1TIME        = origen.V1TIME,
            VCON          = origen.VCON,
            VPHONE        = origen.VPHONE,
            VTAX          = origen.VTAX,
            VTAXCD        = origen.VTAXCD,
            VMIDNM        = origen.VMIDNM,
            V1099         = origen.V1099,
            V1099C        = origen.V1099C,
            VDTLPD        = origen.VDTLPD,
            VPYTYR        = origen.VPYTYR,
            VDPURS        = origen.VDPURS,
            VHOLD         = origen.VHOLD,
            VNSTAT        = origen.VNSTAT,
            VMBANK        = origen.VMBANK,
            VMBNKC        = origen.VMBNKC,
            VMBRNO        = origen.VMBRNO,
            VMBNKA        = origen.VMBNKA,
            VMCARR        = origen.VMCARR,
            VMMNTR        = origen.VMMNTR,
            VMLANG        = origen.VMLANG,
            EsVigente     = 1,
            HashDiff      = origen.HashDiff,
            FechaCargaInt = SYSDATETIME(),
            RunId         = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (
            VENDOR, VMID, VNDNAM, VNALPH, VNDAD1, VNDAD2, VSTATE, VCOUN, VTYPE, VCMPNY,
            VTERMS, VPAYTO, VCURR, VPAYTY, V1TIME, VCON, VPHONE, VTAX, VTAXCD, VMIDNM,
            V1099, V1099C, VDTLPD, VPYTYR, VDPURS, VHOLD, VNSTAT,
            VMBANK, VMBNKC, VMBRNO, VMBNKA, VMCARR, VMMNTR, VMLANG,
            HashDiff, RunId
        )
        VALUES (
            origen.VENDOR, origen.VMID, origen.VNDNAM, origen.VNALPH, origen.VNDAD1, origen.VNDAD2, origen.VSTATE, origen.VCOUN, origen.VTYPE, origen.VCMPNY,
            origen.VTERMS, origen.VPAYTO, origen.VCURR, origen.VPAYTY, origen.V1TIME, origen.VCON, origen.VPHONE, origen.VTAX, origen.VTAXCD, origen.VMIDNM,
            origen.V1099, origen.V1099C, origen.VDTLPD, origen.VPYTYR, origen.VDPURS, origen.VHOLD, origen.VNSTAT,
            origen.VMBANK, origen.VMBNKC, origen.VMBRNO, origen.VMBNKA, origen.VMCARR, origen.VMMNTR, origen.VMLANG,
            origen.HashDiff, @RunId
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
            CAST(CASE WHEN VMID = 'VM' THEN 1 ELSE 0 END AS BIT) AS EsActivo,
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
            EsActivo                     = origen.EsActivo,
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
            CodigoProveedor, EsActivo, NombreProveedor, ClaveBusqueda, Direccion1, Direccion2,
            CodigoEstado, CodigoPais, TipoProveedor, CodigoEmpresa, CodigoTerminos,
            ProveedorPagoA, CodigoMoneda, MetodoPago, ProveedorUnaVez, NombreContacto, Telefono,
            CostoIncluyeImpuesto, CodigoImpuesto, NumeroIdentificacionFiscal, TipoProveedor1099, Codigo1099,
            FechaUltimoPago, PagosAnioActual, ComprasAnioActual, CodigoRetencion, EstadoProveedor,
            CodigoBanco, CodigoBancoDetalle, SucursalBancaria, CuentaBancaria,
            Transportista, MedioTransporte, Idioma,
            EsVigente, HashDiff, RunId
        )
        VALUES (
            origen.CodigoProveedor, origen.EsActivo, origen.NombreProveedor, origen.ClaveBusqueda, origen.Direccion1, origen.Direccion2,
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

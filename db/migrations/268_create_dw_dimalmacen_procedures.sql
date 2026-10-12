-- 268: merge Silver -> Gold para dimAlmacen. SCD Tipo 1 (sobrescribe).
-- Reutiliza el HashDiff de [int].dimAlmacen. EmpresaKey/PaisKey via LEFT JOIN
-- (codigos unicos en dw, no duplica filas); tambien se actualiza cuando solo
-- cambia la llave, para completar llaves que llegan despues. Correr despues de
-- dimEmpresas y dimPais.

CREATE OR ALTER PROCEDURE dw.usp_MergeDimAlmacen
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].dimAlmacen);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH Origen AS (
        SELECT
            a.LWHS    AS CodigoAlmacen,
            a.LID     AS TipoRegistro,
            CAST(CASE WHEN a.LID = 'WM' THEN 1 ELSE 0 END AS BIT) AS EsActivo,
            a.LDESC   AS Descripcion,
            e.EmpresaKey,
            a.WMCOMP  AS CodigoEmpresa,
            a.WMFAC   AS CodigoFacilidad,
            a.LADD1   AS Direccion1,
            a.LADD2   AS Direccion2,
            a.LADD3   AS Direccion3,
            ps.PaisKey,
            a.LCOUN   AS CodigoPais,
            a.WMSTE   AS CodigoEstado,
            a.LPOAS   AS CodigoPostal,
            a.LPHON   AS Telefono,
            a.WMFAXN  AS Fax,
            a.LALWH   AS AlmacenAsignable,
            a.LNETW   AS AlmacenNeteable,
            a.WMNCST  AS CosteaMaterial,
            a.LFRFG   AS UsaPronostico,
            a.WMMNWH  AS TipoAlmacen,
            a.WMALRQ  AS RequiereAsignacion,
            a.WMDYP   AS ToleranciaDiasMas,
            a.WMDYM   AS ToleranciaDiasMenos,
            a.WMTYP   AS ToleranciaCantidadMasPct,
            a.WMTYM   AS ToleranciaCantidadMenosPct,
            a.WMAUTO  AS CierreAutomatico,
            a.WMRLOC  AS UbicacionRecepcion,
            a.WMSLOC  AS UbicacionEnvio,
            a.WMLANG  AS Idioma,
            a.LLDTE   AS FechaUltimaTransaccion,
            a.WMCBY   AS UsuarioCreacion,
            a.WMCDT   AS FechaCreacion,
            a.WMCTM   AS HoraCreacion,
            a.WMLUSR  AS UsuarioModificacion,
            a.WFLDTE  AS FechaModificacion,
            a.WFLTME  AS HoraModificacion,
            a.EsVigente,
            a.HashDiff
        FROM [int].dimAlmacen a
        LEFT JOIN dw.dimEmpresas e ON e.CodigoEmpresa = a.WMCOMP
        LEFT JOIN dw.dimPais ps    ON ps.CodigoPaisAlpha3 = a.LCOUN
    )
    MERGE dw.dimAlmacen AS destino
        USING Origen AS origen
        ON destino.CodigoAlmacen = origen.CodigoAlmacen
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente
                      OR ISNULL(destino.EmpresaKey, -1) <> ISNULL(origen.EmpresaKey, -1)
                      OR ISNULL(destino.PaisKey, -1) <> ISNULL(origen.PaisKey, -1)) THEN
        UPDATE SET
            TipoRegistro               = origen.TipoRegistro,
            EsActivo                   = origen.EsActivo,
            Descripcion                = origen.Descripcion,
            EmpresaKey                 = origen.EmpresaKey,
            CodigoEmpresa              = origen.CodigoEmpresa,
            CodigoFacilidad            = origen.CodigoFacilidad,
            Direccion1                 = origen.Direccion1,
            Direccion2                 = origen.Direccion2,
            Direccion3                 = origen.Direccion3,
            PaisKey                    = origen.PaisKey,
            CodigoPais                 = origen.CodigoPais,
            CodigoEstado               = origen.CodigoEstado,
            CodigoPostal               = origen.CodigoPostal,
            Telefono                   = origen.Telefono,
            Fax                        = origen.Fax,
            AlmacenAsignable           = origen.AlmacenAsignable,
            AlmacenNeteable            = origen.AlmacenNeteable,
            CosteaMaterial             = origen.CosteaMaterial,
            UsaPronostico              = origen.UsaPronostico,
            TipoAlmacen                = origen.TipoAlmacen,
            RequiereAsignacion         = origen.RequiereAsignacion,
            ToleranciaDiasMas          = origen.ToleranciaDiasMas,
            ToleranciaDiasMenos        = origen.ToleranciaDiasMenos,
            ToleranciaCantidadMasPct   = origen.ToleranciaCantidadMasPct,
            ToleranciaCantidadMenosPct = origen.ToleranciaCantidadMenosPct,
            CierreAutomatico           = origen.CierreAutomatico,
            UbicacionRecepcion         = origen.UbicacionRecepcion,
            UbicacionEnvio             = origen.UbicacionEnvio,
            Idioma                     = origen.Idioma,
            FechaUltimaTransaccion     = origen.FechaUltimaTransaccion,
            UsuarioCreacion            = origen.UsuarioCreacion,
            FechaCreacion              = origen.FechaCreacion,
            HoraCreacion               = origen.HoraCreacion,
            UsuarioModificacion        = origen.UsuarioModificacion,
            FechaModificacion          = origen.FechaModificacion,
            HoraModificacion           = origen.HoraModificacion,
            EsVigente                  = origen.EsVigente,
            HashDiff                   = origen.HashDiff,
            FechaCargaDw               = SYSDATETIME(),
            RunId                      = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (CodigoAlmacen, TipoRegistro, EsActivo, Descripcion, EmpresaKey, CodigoEmpresa, CodigoFacilidad,
                Direccion1, Direccion2, Direccion3, PaisKey, CodigoPais, CodigoEstado, CodigoPostal, Telefono, Fax,
                AlmacenAsignable, AlmacenNeteable, CosteaMaterial, UsaPronostico, TipoAlmacen, RequiereAsignacion,
                ToleranciaDiasMas, ToleranciaDiasMenos, ToleranciaCantidadMasPct, ToleranciaCantidadMenosPct,
                CierreAutomatico, UbicacionRecepcion, UbicacionEnvio, Idioma, FechaUltimaTransaccion,
                UsuarioCreacion, FechaCreacion, HoraCreacion, UsuarioModificacion, FechaModificacion,
                HoraModificacion, EsVigente, HashDiff, RunId)
        VALUES (origen.CodigoAlmacen, origen.TipoRegistro, origen.EsActivo, origen.Descripcion, origen.EmpresaKey,
                origen.CodigoEmpresa, origen.CodigoFacilidad, origen.Direccion1, origen.Direccion2, origen.Direccion3,
                origen.PaisKey, origen.CodigoPais, origen.CodigoEstado, origen.CodigoPostal, origen.Telefono, origen.Fax,
                origen.AlmacenAsignable, origen.AlmacenNeteable, origen.CosteaMaterial, origen.UsaPronostico,
                origen.TipoAlmacen, origen.RequiereAsignacion, origen.ToleranciaDiasMas, origen.ToleranciaDiasMenos,
                origen.ToleranciaCantidadMasPct, origen.ToleranciaCantidadMenosPct, origen.CierreAutomatico,
                origen.UbicacionRecepcion, origen.UbicacionEnvio, origen.Idioma, origen.FechaUltimaTransaccion,
                origen.UsuarioCreacion, origen.FechaCreacion, origen.HoraCreacion, origen.UsuarioModificacion,
                origen.FechaModificacion, origen.HoraModificacion, origen.EsVigente, origen.HashDiff, @RunId)
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

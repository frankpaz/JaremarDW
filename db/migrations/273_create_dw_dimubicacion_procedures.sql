-- 273: merge Silver -> Gold para dimUbicacion. SCD Tipo 1 (sobrescribe).
-- Reutiliza el HashDiff de [int].dimUbicacion. AlmacenKey via LEFT JOIN; tambien se
-- actualiza cuando solo cambia la llave (almacen dado de alta despues). Correr
-- despues de dimAlmacen.

CREATE OR ALTER PROCEDURE dw.usp_MergeDimUbicacion
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].dimUbicacion);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH Origen AS (
        SELECT
            u.WWHS    AS CodigoAlmacen,
            u.WLOC    AS CodigoUbicacion,
            a.AlmacenKey,
            u.WID     AS TipoRegistro,
            CAST(CASE WHEN u.WID = 'WL' THEN 1 ELSE 0 END AS BIT) AS EsActivo,
            u.WDESC   AS Descripcion,
            u.LMPRF   AS CodigoCentroBeneficio,
            u.WLTYP   AS TipoUbicacion,
            u.WZONE   AS Zona,
            u.WCYCI   AS DiasConteoCiclico,
            u.WCONC   AS MaximoTarimas,
            u.WALLC   AS UbicacionAsignable,
            u.WFLOC   AS UbicacionForzadaDefecto,
            u.EsVigente,
            u.HashDiff
        FROM [int].dimUbicacion u
        LEFT JOIN dw.dimAlmacen a ON a.CodigoAlmacen = u.WWHS
    )
    MERGE dw.dimUbicacion AS destino
        USING Origen AS origen
        ON destino.CodigoAlmacen = origen.CodigoAlmacen AND destino.CodigoUbicacion = origen.CodigoUbicacion
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente
                      OR ISNULL(destino.AlmacenKey, -1) <> ISNULL(origen.AlmacenKey, -1)) THEN
        UPDATE SET
            AlmacenKey              = origen.AlmacenKey,
            TipoRegistro            = origen.TipoRegistro,
            EsActivo                = origen.EsActivo,
            Descripcion             = origen.Descripcion,
            CodigoCentroBeneficio   = origen.CodigoCentroBeneficio,
            TipoUbicacion           = origen.TipoUbicacion,
            Zona                    = origen.Zona,
            DiasConteoCiclico       = origen.DiasConteoCiclico,
            MaximoTarimas           = origen.MaximoTarimas,
            UbicacionAsignable      = origen.UbicacionAsignable,
            UbicacionForzadaDefecto = origen.UbicacionForzadaDefecto,
            EsVigente               = origen.EsVigente,
            HashDiff                = origen.HashDiff,
            FechaCargaDw            = SYSDATETIME(),
            RunId                   = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (CodigoAlmacen, CodigoUbicacion, AlmacenKey, TipoRegistro, EsActivo, Descripcion,
                CodigoCentroBeneficio, TipoUbicacion, Zona, DiasConteoCiclico, MaximoTarimas,
                UbicacionAsignable, UbicacionForzadaDefecto, EsVigente, HashDiff, RunId)
        VALUES (origen.CodigoAlmacen, origen.CodigoUbicacion, origen.AlmacenKey, origen.TipoRegistro,
                origen.EsActivo, origen.Descripcion, origen.CodigoCentroBeneficio, origen.TipoUbicacion,
                origen.Zona, origen.DiasConteoCiclico, origen.MaximoTarimas, origen.UbicacionAsignable,
                origen.UbicacionForzadaDefecto, origen.EsVigente, origen.HashDiff, @RunId)
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

-- 010: merge Silver -> Gold para dimProducto. SCD Tipo 1 (sobrescribe).
-- Reutiliza el HashDiff ya calculado en [int].dimProducto -- no se recalcula.

CREATE OR ALTER PROCEDURE dw.usp_MergeDimProducto
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].dimProducto);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH Origen AS (
        SELECT
            IPROD  AS CodigoProducto,
            IDESC  AS Descripcion,
            ICLAS  AS ClaseItem,
            IUMS   AS UMAlmacen,
            IUMP   AS UMCompra,
            ILDTE  AS FechaUltimaTransaccion,
            IMMNDT AS FechaUltimaModificacion,
            IMMNTM AS HoraUltimaModificacion,
            EsVigente,
            HashDiff
        FROM [int].dimProducto
    )
    MERGE dw.dimProducto AS destino
    USING Origen AS origen
        ON destino.CodigoProducto = origen.CodigoProducto
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente) THEN
        UPDATE SET
            Descripcion             = origen.Descripcion,
            ClaseItem               = origen.ClaseItem,
            UMAlmacen               = origen.UMAlmacen,
            UMCompra                = origen.UMCompra,
            FechaUltimaTransaccion  = origen.FechaUltimaTransaccion,
            FechaUltimaModificacion = origen.FechaUltimaModificacion,
            HoraUltimaModificacion  = origen.HoraUltimaModificacion,
            EsVigente               = origen.EsVigente,
            HashDiff                = origen.HashDiff,
            FechaCargaDw            = SYSDATETIME(),
            RunId                   = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (CodigoProducto, Descripcion, ClaseItem, UMAlmacen, UMCompra,
                FechaUltimaTransaccion, FechaUltimaModificacion, HoraUltimaModificacion,
                EsVigente, HashDiff, RunId)
        VALUES (origen.CodigoProducto, origen.Descripcion, origen.ClaseItem, origen.UMAlmacen, origen.UMCompra,
                origen.FechaUltimaTransaccion, origen.FechaUltimaModificacion, origen.HoraUltimaModificacion,
                origen.EsVigente, origen.HashDiff, @RunId)
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

-- 127: merge Silver -> Gold para dimTerminosCompra. SCD Tipo 1 (sobrescribe).
-- Reutiliza el HashDiff ya calculado en [int].dimTerminosCompra.

CREATE OR ALTER PROCEDURE dw.usp_MergeDimTerminosCompra
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].dimTerminosCompra);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH Origen AS (
        SELECT
            VTERM  AS CodigoTerminos,
            VTMDSC AS Descripcion,
            VTMDDY AS DiasVencimiento,
            VTTAXD AS ImpuestoAntesDescuento,
            EsVigente,
            HashDiff
        FROM [int].dimTerminosCompra
    )
    MERGE dw.dimTerminosCompra AS destino
        USING Origen AS origen
        ON destino.CodigoTerminos = origen.CodigoTerminos
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente) THEN
        UPDATE SET
            Descripcion            = origen.Descripcion,
            DiasVencimiento        = origen.DiasVencimiento,
            ImpuestoAntesDescuento = origen.ImpuestoAntesDescuento,
            EsVigente              = origen.EsVigente,
            HashDiff               = origen.HashDiff,
            FechaCargaDw           = SYSDATETIME(),
            RunId                  = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (CodigoTerminos, Descripcion, DiasVencimiento, ImpuestoAntesDescuento, EsVigente, HashDiff, RunId)
        VALUES (origen.CodigoTerminos, origen.Descripcion, origen.DiasVencimiento, origen.ImpuestoAntesDescuento, origen.EsVigente, origen.HashDiff, @RunId)
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

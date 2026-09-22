-- 123: merge Silver -> Gold para dimTerminosVenta. SCD Tipo 1 (sobrescribe).
-- Reutiliza el HashDiff ya calculado en [int].dimTerminosVenta.

CREATE OR ALTER PROCEDURE dw.usp_MergeDimTerminosVenta
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].dimTerminosVenta);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH Origen AS (
        SELECT
            TMCMPN AS NumeroEmpresa,
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
        ON destino.NumeroEmpresa = origen.NumeroEmpresa AND destino.CodigoTerminos = origen.CodigoTerminos
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
        INSERT (NumeroEmpresa, CodigoTerminos, Descripcion, DiasVencimiento, ImpuestoAntesDescuento, ImpuestoSobreNetoDescuento, PagoContraOrden, EsVigente, HashDiff, RunId)
        VALUES (origen.NumeroEmpresa, origen.CodigoTerminos, origen.Descripcion, origen.DiasVencimiento, origen.ImpuestoAntesDescuento, origen.ImpuestoSobreNetoDescuento, origen.PagoContraOrden, origen.EsVigente, origen.HashDiff, @RunId)
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

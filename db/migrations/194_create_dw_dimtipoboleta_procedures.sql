-- 194: merge Silver -> Gold para dimTipoBoleta. SCD Tipo 1 (sobrescribe).
-- Reutiliza el HashDiff ya calculado en [int].dimTipoBoleta.

CREATE OR ALTER PROCEDURE dw.usp_MergeDimTipoBoleta
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].dimTipoBoleta);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH Origen AS (
        SELECT
            BOLETY AS CodigoTipoBoleta,
            DESTYP AS DescripcionTipoBoleta,
            BENVIO AS IndicadorEnvio,
            BINOUT AS IndicadorIngresoSalida,
            BTOLEP AS ToleranciaPositivaPct,
            BTOLEN AS ToleranciaNegativaPct,
            EsVigente,
            HashDiff
        FROM [int].dimTipoBoleta
    )
    MERGE dw.dimTipoBoleta AS destino
        USING Origen AS origen
        ON destino.CodigoTipoBoleta = origen.CodigoTipoBoleta
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente) THEN
        UPDATE SET
            DescripcionTipoBoleta    = origen.DescripcionTipoBoleta,
            IndicadorEnvio           = origen.IndicadorEnvio,
            IndicadorIngresoSalida   = origen.IndicadorIngresoSalida,
            ToleranciaPositivaPct    = origen.ToleranciaPositivaPct,
            ToleranciaNegativaPct    = origen.ToleranciaNegativaPct,
            EsVigente                = origen.EsVigente,
            HashDiff                 = origen.HashDiff,
            FechaCargaDw             = SYSDATETIME(),
            RunId                    = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (CodigoTipoBoleta, DescripcionTipoBoleta, IndicadorEnvio, IndicadorIngresoSalida, ToleranciaPositivaPct, ToleranciaNegativaPct, EsVigente, HashDiff, RunId)
        VALUES (origen.CodigoTipoBoleta, origen.DescripcionTipoBoleta, origen.IndicadorEnvio, origen.IndicadorIngresoSalida, origen.ToleranciaPositivaPct, origen.ToleranciaNegativaPct, origen.EsVigente, origen.HashDiff, @RunId)
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

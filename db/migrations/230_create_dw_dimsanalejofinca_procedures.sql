-- 230: merge Silver -> Gold para dimSanAlejoFinca (dominio SanAlejo). SCD Tipo 1 (sobrescribe).
-- Reutiliza el HashDiff ya calculado en [int].dimSanAlejoFinca.

CREATE OR ALTER PROCEDURE dw.usp_MergeDimSanAlejoFinca
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].dimSanAlejoFinca);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH Origen AS (
        SELECT
            [CODCIA] AS CodigoEmpresa,
            [FINCA] AS CodigoFinca,
            [CODSUC] AS CodigoSucursal,
            [FRENTE] AS FrenteCosecha,
            [EXTEN] AS ExtensionHectareas,
            [DESFIN] AS DescripcionFinca,
            [VARIED] AS Variedad,
            [PREFFB] AS PrecioTMFFB,
            [NOPLA] AS CodigoPlanilla,
            [CIAREL] AS CompaniaRelacionada,
            [STATUS] AS Estatus,
            EsVigente,
            HashDiff
        FROM [int].dimSanAlejoFinca
    )
    MERGE dw.dimSanAlejoFinca AS destino
        USING Origen AS origen
        ON destino.CodigoEmpresa = origen.CodigoEmpresa AND destino.CodigoFinca = origen.CodigoFinca
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente) THEN
        UPDATE SET
            CodigoSucursal        = origen.CodigoSucursal,
            FrenteCosecha         = origen.FrenteCosecha,
            ExtensionHectareas    = origen.ExtensionHectareas,
            DescripcionFinca      = origen.DescripcionFinca,
            Variedad              = origen.Variedad,
            PrecioTMFFB           = origen.PrecioTMFFB,
            CodigoPlanilla        = origen.CodigoPlanilla,
            CompaniaRelacionada   = origen.CompaniaRelacionada,
            Estatus               = origen.Estatus,
            EsVigente             = origen.EsVigente,
            HashDiff              = origen.HashDiff,
            FechaCargaDw          = SYSDATETIME(),
            RunId                 = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (CodigoEmpresa, CodigoFinca, CodigoSucursal, FrenteCosecha, ExtensionHectareas, DescripcionFinca, Variedad, PrecioTMFFB, CodigoPlanilla, CompaniaRelacionada, Estatus, EsVigente, HashDiff, RunId)
        VALUES (origen.CodigoEmpresa, origen.CodigoFinca, origen.CodigoSucursal, origen.FrenteCosecha, origen.ExtensionHectareas, origen.DescripcionFinca, origen.Variedad, origen.PrecioTMFFB, origen.CodigoPlanilla, origen.CompaniaRelacionada, origen.Estatus, origen.EsVigente, origen.HashDiff, @RunId)
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

-- 226: merge Silver -> Gold para dimSanAlejoProductor (dominio SanAlejo). SCD Tipo 1 (sobrescribe).
-- Reutiliza el HashDiff ya calculado en [int].dimSanAlejoProductor.

CREATE OR ALTER PROCEDURE dw.usp_MergeDimSanAlejoProductor
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].dimSanAlejoProductor);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH Origen AS (
        SELECT
            [CODCIA] AS CodigoEmpresa,
            [CODPRO] AS CodigoProductor,
            [NOMPRO] AS NombreProductor,
            [UBICA] AS UbicacionFinca,
            [SECTOR] AS Sector,
            [ESTADO] AS Estado,
            [TOTHEC] AS TotalHectareas,
            [NUMCON] AS NumeroContrato,
            [FECCON] AS FechaInicioContrato,
            [FECFIN] AS FechaFinContrato,
            [CODLOC] AS CodigoLocalizacion,
            [CODANT] AS CodigoAnterior,
            EsVigente,
            HashDiff
        FROM [int].dimSanAlejoProductor
    )
    MERGE dw.dimSanAlejoProductor AS destino
        USING Origen AS origen
        ON destino.CodigoEmpresa = origen.CodigoEmpresa AND destino.CodigoProductor = origen.CodigoProductor
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente) THEN
        UPDATE SET
            NombreProductor       = origen.NombreProductor,
            UbicacionFinca        = origen.UbicacionFinca,
            Sector                = origen.Sector,
            Estado                = origen.Estado,
            TotalHectareas        = origen.TotalHectareas,
            NumeroContrato        = origen.NumeroContrato,
            FechaInicioContrato   = origen.FechaInicioContrato,
            FechaFinContrato      = origen.FechaFinContrato,
            CodigoLocalizacion    = origen.CodigoLocalizacion,
            CodigoAnterior        = origen.CodigoAnterior,
            EsVigente             = origen.EsVigente,
            HashDiff              = origen.HashDiff,
            FechaCargaDw          = SYSDATETIME(),
            RunId                 = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (CodigoEmpresa, CodigoProductor, NombreProductor, UbicacionFinca, Sector, Estado, TotalHectareas, NumeroContrato, FechaInicioContrato, FechaFinContrato, CodigoLocalizacion, CodigoAnterior, EsVigente, HashDiff, RunId)
        VALUES (origen.CodigoEmpresa, origen.CodigoProductor, origen.NombreProductor, origen.UbicacionFinca, origen.Sector, origen.Estado, origen.TotalHectareas, origen.NumeroContrato, origen.FechaInicioContrato, origen.FechaFinContrato, origen.CodigoLocalizacion, origen.CodigoAnterior, origen.EsVigente, origen.HashDiff, @RunId)
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

-- 026: merge Silver -> Gold para dimCentroCosto. SCD Tipo 1 (sobrescribe).
-- Reutiliza el HashDiff ya calculado en [int].dimCentroCosto.

CREATE OR ALTER PROCEDURE dw.usp_MergeDimCentroCosto
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].dimCentroCosto);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH Origen AS (
        SELECT
            SVSGVL AS CodigoCentroCosto,
            SVID,
            SVLDES AS DescripcionCentroCosto,
            SVDATE AS FechaRegistro,
            SVTIME AS HoraRegistro,
            EsVigente,
            HashDiff
        FROM [int].dimCentroCosto
    )
    MERGE dw.dimCentroCosto AS destino
        USING Origen AS origen
        ON destino.CodigoCentroCosto = origen.CodigoCentroCosto
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente) THEN
        UPDATE SET
            SVID                    = origen.SVID,
            DescripcionCentroCosto  = origen.DescripcionCentroCosto,
            FechaRegistro           = origen.FechaRegistro,
            HoraRegistro            = origen.HoraRegistro,
            EsVigente               = origen.EsVigente,
            HashDiff                = origen.HashDiff,
            FechaCargaDw            = SYSDATETIME(),
            RunId                   = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (CodigoCentroCosto, SVID, DescripcionCentroCosto, FechaRegistro, HoraRegistro, EsVigente, HashDiff, RunId)
        VALUES (origen.CodigoCentroCosto, origen.SVID, origen.DescripcionCentroCosto, origen.FechaRegistro, origen.HoraRegistro,
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

-- 030: merge Silver -> Gold para dimCuenta. SCD Tipo 1 (sobrescribe).
-- Reutiliza el HashDiff ya calculado en [int].dimCuenta.

CREATE OR ALTER PROCEDURE dw.usp_MergeDimCuenta
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].dimCuenta);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH Origen AS (
        SELECT
            SVSGVL AS CodigoCuenta,
            SVID,
            SVLDES AS DescripcionCuenta,
            SVDATE AS FechaRegistro,
            SVTIME AS HoraRegistro,
            EsVigente,
            HashDiff
        FROM [int].dimCuenta
    )
    MERGE dw.dimCuenta AS destino
        USING Origen AS origen
        ON destino.CodigoCuenta = origen.CodigoCuenta
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente) THEN
        UPDATE SET
            SVID               = origen.SVID,
            DescripcionCuenta  = origen.DescripcionCuenta,
            FechaRegistro      = origen.FechaRegistro,
            HoraRegistro       = origen.HoraRegistro,
            EsVigente          = origen.EsVigente,
            HashDiff           = origen.HashDiff,
            FechaCargaDw       = SYSDATETIME(),
            RunId              = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (CodigoCuenta, SVID, DescripcionCuenta, FechaRegistro, HoraRegistro, EsVigente, HashDiff, RunId)
        VALUES (origen.CodigoCuenta, origen.SVID, origen.DescripcionCuenta, origen.FechaRegistro, origen.HoraRegistro,
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

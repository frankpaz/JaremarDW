-- 034: merge Silver -> Gold para dimSubCuenta. SCD Tipo 1 (sobrescribe).
-- Reutiliza el HashDiff ya calculado en [int].dimSubCuenta.

CREATE OR ALTER PROCEDURE dw.usp_MergeDimSubCuenta
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].dimSubCuenta);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH Origen AS (
        SELECT
            SVSGVL AS CodigoSubCuenta,
            SVID,
            SVLDES AS DescripcionSubCuenta,
            SVDATE AS FechaRegistro,
            SVTIME AS HoraRegistro,
            EsVigente,
            HashDiff
        FROM [int].dimSubCuenta
    )
    MERGE dw.dimSubCuenta AS destino
        USING Origen AS origen
        ON destino.CodigoSubCuenta = origen.CodigoSubCuenta
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente) THEN
        UPDATE SET
            SVID                  = origen.SVID,
            DescripcionSubCuenta  = origen.DescripcionSubCuenta,
            FechaRegistro         = origen.FechaRegistro,
            HoraRegistro          = origen.HoraRegistro,
            EsVigente             = origen.EsVigente,
            HashDiff              = origen.HashDiff,
            FechaCargaDw          = SYSDATETIME(),
            RunId                 = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (CodigoSubCuenta, SVID, DescripcionSubCuenta, FechaRegistro, HoraRegistro, EsVigente, HashDiff, RunId)
        VALUES (origen.CodigoSubCuenta, origen.SVID, origen.DescripcionSubCuenta, origen.FechaRegistro, origen.HoraRegistro,
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

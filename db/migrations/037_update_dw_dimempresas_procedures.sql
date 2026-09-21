-- 037: usp_MergeDimEmpresas (Gold) ahora tambien lleva CodigoMoneda.

CREATE OR ALTER PROCEDURE dw.usp_MergeDimEmpresas
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].dimEmpresas);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH Origen AS (
        SELECT
            SVSGVL AS CodigoEmpresa,
            SVID,
            SVLDES AS RazonSocial,
            SVDATE AS FechaRegistro,
            SVTIME AS HoraRegistro,
            MonedaFuncional AS CodigoMoneda,
            EsVigente,
            HashDiff
        FROM [int].dimEmpresas
    )
    MERGE dw.dimEmpresas AS destino
        USING Origen AS origen
        ON destino.CodigoEmpresa = origen.CodigoEmpresa
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente) THEN
        UPDATE SET
            SVID           = origen.SVID,
            RazonSocial    = origen.RazonSocial,
            FechaRegistro  = origen.FechaRegistro,
            HoraRegistro   = origen.HoraRegistro,
            CodigoMoneda   = origen.CodigoMoneda,
            EsVigente      = origen.EsVigente,
            HashDiff       = origen.HashDiff,
            FechaCargaDw   = SYSDATETIME(),
            RunId          = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (CodigoEmpresa, SVID, RazonSocial, FechaRegistro, HoraRegistro, CodigoMoneda, EsVigente, HashDiff, RunId)
        VALUES (origen.CodigoEmpresa, origen.SVID, origen.RazonSocial, origen.FechaRegistro, origen.HoraRegistro,
                origen.CodigoMoneda, origen.EsVigente, origen.HashDiff, @RunId)
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

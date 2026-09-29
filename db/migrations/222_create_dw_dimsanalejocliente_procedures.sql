-- 222: merge Silver -> Gold para dimSanAlejoCliente (dominio SanAlejo). SCD Tipo 1 (sobrescribe).
-- Reutiliza el HashDiff ya calculado en [int].dimSanAlejoCliente.

CREATE OR ALTER PROCEDURE dw.usp_MergeDimSanAlejoCliente
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].dimSanAlejoCliente);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH Origen AS (
        SELECT
            [CODCIA] AS CodigoEmpresa,
            [CODCLI] AS CodigoCliente,
            [NOMCLI] AS NombreCliente,
            [DIRCLI] AS DireccionCliente,
            EsVigente,
            HashDiff
        FROM [int].dimSanAlejoCliente
    )
    MERGE dw.dimSanAlejoCliente AS destino
        USING Origen AS origen
        ON destino.CodigoEmpresa = origen.CodigoEmpresa AND destino.CodigoCliente = origen.CodigoCliente
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente) THEN
        UPDATE SET
            NombreCliente      = origen.NombreCliente,
            DireccionCliente   = origen.DireccionCliente,
            EsVigente          = origen.EsVigente,
            HashDiff           = origen.HashDiff,
            FechaCargaDw       = SYSDATETIME(),
            RunId              = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (CodigoEmpresa, CodigoCliente, NombreCliente, DireccionCliente, EsVigente, HashDiff, RunId)
        VALUES (origen.CodigoEmpresa, origen.CodigoCliente, origen.NombreCliente, origen.DireccionCliente, origen.EsVigente, origen.HashDiff, @RunId)
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

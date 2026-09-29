-- 210: merge Silver -> Gold para dimSanAlejoProducto (dominio SanAlejo). SCD Tipo 1 (sobrescribe).
-- Reutiliza el HashDiff ya calculado en [int].dimSanAlejoProducto.

CREATE OR ALTER PROCEDURE dw.usp_MergeDimSanAlejoProducto
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].dimSanAlejoProducto);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH Origen AS (
        SELECT
            [COPROD] AS CodigoProducto,
            [NOPROD] AS NombreProducto,
            [CODALT] AS CodigoAlternoLX,
            [UNIMED] AS UnidadMedida,
            [PREPRO] AS PrecioProducto,
            [CERTIF] AS CertificadoRSPO,
            EsVigente,
            HashDiff
        FROM [int].dimSanAlejoProducto
    )
    MERGE dw.dimSanAlejoProducto AS destino
        USING Origen AS origen
        ON destino.CodigoProducto = origen.CodigoProducto
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente) THEN
        UPDATE SET
            NombreProducto    = origen.NombreProducto,
            CodigoAlternoLX   = origen.CodigoAlternoLX,
            UnidadMedida      = origen.UnidadMedida,
            PrecioProducto    = origen.PrecioProducto,
            CertificadoRSPO   = origen.CertificadoRSPO,
            EsVigente         = origen.EsVigente,
            HashDiff          = origen.HashDiff,
            FechaCargaDw      = SYSDATETIME(),
            RunId             = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (CodigoProducto, NombreProducto, CodigoAlternoLX, UnidadMedida, PrecioProducto, CertificadoRSPO, EsVigente, HashDiff, RunId)
        VALUES (origen.CodigoProducto, origen.NombreProducto, origen.CodigoAlternoLX, origen.UnidadMedida, origen.PrecioProducto, origen.CertificadoRSPO, origen.EsVigente, origen.HashDiff, @RunId)
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

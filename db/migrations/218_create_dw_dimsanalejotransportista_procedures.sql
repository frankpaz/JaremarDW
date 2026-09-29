-- 218: merge Silver -> Gold para dimSanAlejoTransportista (dominio SanAlejo). SCD Tipo 1 (sobrescribe).
-- Reutiliza el HashDiff ya calculado en [int].dimSanAlejoTransportista.

CREATE OR ALTER PROCEDURE dw.usp_MergeDimSanAlejoTransportista
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].dimSanAlejoTransportista);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH Origen AS (
        SELECT
            [CODCIA] AS CodigoEmpresa,
            [CODTRA] AS CodigoTransportista,
            [NOMTRA] AS NombreTransportista,
            [VALKIL] AS ValorKilometro,
            [PRECIO] AS Precio,
            [CODALX] AS CodigoAlternoLX,
            EsVigente,
            HashDiff
        FROM [int].dimSanAlejoTransportista
    )
    MERGE dw.dimSanAlejoTransportista AS destino
        USING Origen AS origen
        ON destino.CodigoEmpresa = origen.CodigoEmpresa AND destino.CodigoTransportista = origen.CodigoTransportista
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente) THEN
        UPDATE SET
            NombreTransportista   = origen.NombreTransportista,
            ValorKilometro        = origen.ValorKilometro,
            Precio                = origen.Precio,
            CodigoAlternoLX       = origen.CodigoAlternoLX,
            EsVigente             = origen.EsVigente,
            HashDiff              = origen.HashDiff,
            FechaCargaDw          = SYSDATETIME(),
            RunId                 = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (CodigoEmpresa, CodigoTransportista, NombreTransportista, ValorKilometro, Precio, CodigoAlternoLX, EsVigente, HashDiff, RunId)
        VALUES (origen.CodigoEmpresa, origen.CodigoTransportista, origen.NombreTransportista, origen.ValorKilometro, origen.Precio, origen.CodigoAlternoLX, origen.EsVigente, origen.HashDiff, @RunId)
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

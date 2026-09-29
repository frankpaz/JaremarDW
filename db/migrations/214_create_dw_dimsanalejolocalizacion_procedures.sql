-- 214: merge Silver -> Gold para dimSanAlejoLocalizacion (dominio SanAlejo). SCD Tipo 1 (sobrescribe).
-- Reutiliza el HashDiff ya calculado en [int].dimSanAlejoLocalizacion.

CREATE OR ALTER PROCEDURE dw.usp_MergeDimSanAlejoLocalizacion
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].dimSanAlejoLocalizacion);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH Origen AS (
        SELECT
            [CODCIA] AS CodigoEmpresa,
            [CODLOC] AS CodigoLocalizacion,
            [ORIGEN] AS Origen,
            [DESTIN] AS Destino,
            [PRECTM] AS PrecioTM,
            [COSTOK] AS CostoLibra,
            [CODTAR] AS CodigoTarifaLX,
            [SECTOR] AS Sector,
            [CAMPO1] AS Campo1,
            [MARCA] AS MarcaEliminado,
            EsVigente,
            HashDiff
        FROM [int].dimSanAlejoLocalizacion
    )
    MERGE dw.dimSanAlejoLocalizacion AS destino
        USING Origen AS origen
        ON destino.CodigoEmpresa = origen.CodigoEmpresa AND destino.CodigoLocalizacion = origen.CodigoLocalizacion
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente) THEN
        UPDATE SET
            Origen               = origen.Origen,
            Destino              = origen.Destino,
            PrecioTM             = origen.PrecioTM,
            CostoLibra           = origen.CostoLibra,
            CodigoTarifaLX       = origen.CodigoTarifaLX,
            Sector               = origen.Sector,
            Campo1               = origen.Campo1,
            MarcaEliminado       = origen.MarcaEliminado,
            EsVigente            = origen.EsVigente,
            HashDiff             = origen.HashDiff,
            FechaCargaDw         = SYSDATETIME(),
            RunId                = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (CodigoEmpresa, CodigoLocalizacion, Origen, Destino, PrecioTM, CostoLibra, CodigoTarifaLX, Sector, Campo1, MarcaEliminado, EsVigente, HashDiff, RunId)
        VALUES (origen.CodigoEmpresa, origen.CodigoLocalizacion, origen.Origen, origen.Destino, origen.PrecioTM, origen.CostoLibra, origen.CodigoTarifaLX, origen.Sector, origen.Campo1, origen.MarcaEliminado, origen.EsVigente, origen.HashDiff, @RunId)
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

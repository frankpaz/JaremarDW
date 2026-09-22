-- 132: merge Silver -> Gold para dimPais. SCD Tipo 1 (sobrescribe).
-- Reutiliza el HashDiff ya calculado en [int].dimPais. Resuelve
-- CodigoPaisAlpha2/CodigoPaisNumerico via LEFT JOIN a ref.PaisesIso3166
-- por Alpha3 (LCN/AS400 no trae esos codigos).

CREATE OR ALTER PROCEDURE dw.usp_MergeDimPais
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].dimPais);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH Origen AS (
        SELECT
            i.CNCNTY AS CodigoPaisAlpha3,
            r.Alpha2 AS CodigoPaisAlpha2,
            r.Numerico AS CodigoPaisNumerico,
            i.CNLDSC AS NombrePais,
            i.CNSDSC AS NombreCortoPais,
            i.CNLANG AS CodigoIdioma,
            i.CNCDTE AS FechaCreacion,
            i.CNCTME AS HoraCreacion,
            i.CNCUSR AS UsuarioCreacion,
            i.CNLDTE AS FechaUltimaModificacion,
            i.CNLTME AS HoraUltimaModificacion,
            i.CNLUSR AS UsuarioUltimaModificacion,
            i.EsVigente,
            i.HashDiff
        FROM [int].dimPais i
        LEFT JOIN ref.PaisesIso3166 r ON r.Alpha3 = i.CNCNTY
    )
    MERGE dw.dimPais AS destino
        USING Origen AS origen
        ON destino.CodigoPaisAlpha3 = origen.CodigoPaisAlpha3
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente) THEN
        UPDATE SET
            CodigoPaisAlpha2           = origen.CodigoPaisAlpha2,
            CodigoPaisNumerico         = origen.CodigoPaisNumerico,
            NombrePais                 = origen.NombrePais,
            NombreCortoPais            = origen.NombreCortoPais,
            CodigoIdioma               = origen.CodigoIdioma,
            FechaCreacion              = origen.FechaCreacion,
            HoraCreacion               = origen.HoraCreacion,
            UsuarioCreacion            = origen.UsuarioCreacion,
            FechaUltimaModificacion    = origen.FechaUltimaModificacion,
            HoraUltimaModificacion     = origen.HoraUltimaModificacion,
            UsuarioUltimaModificacion  = origen.UsuarioUltimaModificacion,
            EsVigente                  = origen.EsVigente,
            HashDiff                   = origen.HashDiff,
            FechaCargaDw               = SYSDATETIME(),
            RunId                      = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (
            CodigoPaisAlpha3, CodigoPaisAlpha2, CodigoPaisNumerico, NombrePais, NombreCortoPais, CodigoIdioma,
            FechaCreacion, HoraCreacion, UsuarioCreacion, FechaUltimaModificacion, HoraUltimaModificacion, UsuarioUltimaModificacion,
            EsVigente, HashDiff, RunId
        )
        VALUES (
            origen.CodigoPaisAlpha3, origen.CodigoPaisAlpha2, origen.CodigoPaisNumerico, origen.NombrePais, origen.NombreCortoPais, origen.CodigoIdioma,
            origen.FechaCreacion, origen.HoraCreacion, origen.UsuarioCreacion, origen.FechaUltimaModificacion, origen.HoraUltimaModificacion, origen.UsuarioUltimaModificacion,
            origen.EsVigente, origen.HashDiff, @RunId
        )
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

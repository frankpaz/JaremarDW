-- 145: merge Silver -> Gold para dimRuta. SCD Tipo 1 (sobrescribe).
-- Reutiliza el HashDiff ya calculado en [int].dimRuta.

CREATE OR ALTER PROCEDURE dw.usp_MergeDimRuta
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].dimRuta);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH Origen AS (
        SELECT
            CCCODE AS CodigoRuta,
            CCDESC AS NombreRuta,
            CCENDT AS FechaCreacion,
            CCENTM AS HoraCreacion,
            CCENUS AS UsuarioCreacion,
            CCMNDT AS FechaModificacion,
            CCMNTM AS HoraModificacion,
            CCMNUS AS UsuarioModificacion,
            EsVigente,
            HashDiff
        FROM [int].dimRuta
    )
    MERGE dw.dimRuta AS destino
        USING Origen AS origen
        ON destino.CodigoRuta = origen.CodigoRuta
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente) THEN
        UPDATE SET
            NombreRuta           = origen.NombreRuta,
            FechaCreacion        = origen.FechaCreacion,
            HoraCreacion         = origen.HoraCreacion,
            UsuarioCreacion      = origen.UsuarioCreacion,
            FechaModificacion    = origen.FechaModificacion,
            HoraModificacion     = origen.HoraModificacion,
            UsuarioModificacion  = origen.UsuarioModificacion,
            EsVigente            = origen.EsVigente,
            HashDiff             = origen.HashDiff,
            FechaCargaDw         = SYSDATETIME(),
            RunId                = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (CodigoRuta, NombreRuta, FechaCreacion, HoraCreacion, UsuarioCreacion,
                FechaModificacion, HoraModificacion, UsuarioModificacion, EsVigente, HashDiff, RunId)
        VALUES (origen.CodigoRuta, origen.NombreRuta, origen.FechaCreacion, origen.HoraCreacion, origen.UsuarioCreacion,
                origen.FechaModificacion, origen.HoraModificacion, origen.UsuarioModificacion,
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

-- 165: merge Silver -> Gold para dimViaje. SCD Tipo 1 (sobrescribe).
-- Reutiliza el HashDiff ya calculado en [int].dimViaje.

CREATE OR ALTER PROCEDURE dw.usp_MergeDimViaje
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].dimViaje);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH Origen AS (
        SELECT
            VCODPA AS CodigoViaje,
            VDESC  AS DescripcionViaje,
            VPAGAM AS ValorPagarMotorista,
            VPAGAA AS ValorPagarAyudante,
            VUSUAG AS UsuarioCreacion,
            VFECHG AS FechaCreacion,
            VHORAG AS HoraCreacion,
            VUSUAM AS UsuarioModificacion,
            VFECHM AS FechaModificacion,
            VHORAM AS HoraModificacion,
            VSTS   AS EstatusViaje,
            EsVigente,
            HashDiff
        FROM [int].dimViaje
    )
    MERGE dw.dimViaje AS destino
        USING Origen AS origen
        ON destino.CodigoViaje = origen.CodigoViaje
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente) THEN
        UPDATE SET
            DescripcionViaje     = origen.DescripcionViaje,
            ValorPagarMotorista  = origen.ValorPagarMotorista,
            ValorPagarAyudante   = origen.ValorPagarAyudante,
            UsuarioCreacion      = origen.UsuarioCreacion,
            FechaCreacion        = origen.FechaCreacion,
            HoraCreacion         = origen.HoraCreacion,
            UsuarioModificacion  = origen.UsuarioModificacion,
            FechaModificacion    = origen.FechaModificacion,
            HoraModificacion     = origen.HoraModificacion,
            EstatusViaje         = origen.EstatusViaje,
            EsVigente            = origen.EsVigente,
            HashDiff             = origen.HashDiff,
            FechaCargaDw         = SYSDATETIME(),
            RunId                = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (CodigoViaje, DescripcionViaje, ValorPagarMotorista, ValorPagarAyudante,
                UsuarioCreacion, FechaCreacion, HoraCreacion, UsuarioModificacion, FechaModificacion, HoraModificacion,
                EstatusViaje, EsVigente, HashDiff, RunId)
        VALUES (origen.CodigoViaje, origen.DescripcionViaje, origen.ValorPagarMotorista, origen.ValorPagarAyudante,
                origen.UsuarioCreacion, origen.FechaCreacion, origen.HoraCreacion, origen.UsuarioModificacion,
                origen.FechaModificacion, origen.HoraModificacion, origen.EstatusViaje, origen.EsVigente, origen.HashDiff, @RunId)
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

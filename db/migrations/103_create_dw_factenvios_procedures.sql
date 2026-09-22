-- 103: merge Silver -> Gold para factEnvios. SCD Tipo 1 (sobrescribe).
-- Reutiliza el HashDiff ya calculado en [int].factEnvios. Traduce nombres
-- AS400 a nombre de negocio (ver 102_create_dw_factenvios.sql).

CREATE OR ALTER PROCEDURE dw.usp_MergeFactEnvios
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].factEnvios);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH Origen AS (
        SELECT
            ENCENV AS NumeroEnvio,
            ENCUSU AS UsuarioGenero,
            ENCDSP AS PantallaGeneracion,
            ENCFEC AS FechaGeneracion,
            ENCTIM AS HoraGeneracion,
            ENCCAM AS NumeroCamion,
            ENCPEC AS CapacidadCamionKgs,
            ENCCAD AS PropietarioCamion,
            ENCEMT AS NumeroMotorista,
            ENCEMN AS NombreMotorista,
            ENCEN1 AS NumeroEmpleado1,
            ENCED1 AS NombreEmpleado1,
            ENCEN2 AS NumeroEmpleado2,
            ENCED2 AS NombreEmpleado2,
            ENCEN3 AS NumeroEmpleado3,
            ENCED3 AS NombreEmpleado3,
            ENCEN4 AS NumeroEmpleado4,
            ENCED4 AS NombreEmpleado4,
            ENCROU AS CodigoRuta,
            ENCDER AS DescripcionRuta,
            ENCFEU AS FechaUltimaModificacion,
            ENCTIU AS HoraUltimaModificacion,
            ENCSTA AS EstatusEnvio,
            ENCPES AS PesoTotalEnvio,
            ENCPLA AS NumeroPlaca,
            ENCDT1 AS Dato1,
            ENCPT2 AS Dato2,
            EsVigente,
            HashDiff
        FROM [int].factEnvios
    )
    MERGE dw.factEnvios AS destino
        USING Origen AS origen
        ON destino.NumeroEnvio = origen.NumeroEnvio
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente) THEN
        UPDATE SET
            UsuarioGenero           = origen.UsuarioGenero,
            PantallaGeneracion      = origen.PantallaGeneracion,
            FechaGeneracion         = origen.FechaGeneracion,
            HoraGeneracion          = origen.HoraGeneracion,
            NumeroCamion            = origen.NumeroCamion,
            CapacidadCamionKgs      = origen.CapacidadCamionKgs,
            PropietarioCamion       = origen.PropietarioCamion,
            NumeroMotorista         = origen.NumeroMotorista,
            NombreMotorista         = origen.NombreMotorista,
            NumeroEmpleado1         = origen.NumeroEmpleado1,
            NombreEmpleado1         = origen.NombreEmpleado1,
            NumeroEmpleado2         = origen.NumeroEmpleado2,
            NombreEmpleado2         = origen.NombreEmpleado2,
            NumeroEmpleado3         = origen.NumeroEmpleado3,
            NombreEmpleado3         = origen.NombreEmpleado3,
            NumeroEmpleado4         = origen.NumeroEmpleado4,
            NombreEmpleado4         = origen.NombreEmpleado4,
            CodigoRuta              = origen.CodigoRuta,
            DescripcionRuta         = origen.DescripcionRuta,
            FechaUltimaModificacion = origen.FechaUltimaModificacion,
            HoraUltimaModificacion  = origen.HoraUltimaModificacion,
            EstatusEnvio            = origen.EstatusEnvio,
            PesoTotalEnvio          = origen.PesoTotalEnvio,
            NumeroPlaca             = origen.NumeroPlaca,
            Dato1                   = origen.Dato1,
            Dato2                   = origen.Dato2,
            EsVigente               = origen.EsVigente,
            HashDiff                = origen.HashDiff,
            FechaCargaDw            = SYSDATETIME(),
            RunId                   = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (
            NumeroEnvio, UsuarioGenero, PantallaGeneracion, FechaGeneracion, HoraGeneracion,
            NumeroCamion, CapacidadCamionKgs, PropietarioCamion, NumeroMotorista, NombreMotorista,
            NumeroEmpleado1, NombreEmpleado1, NumeroEmpleado2, NombreEmpleado2,
            NumeroEmpleado3, NombreEmpleado3, NumeroEmpleado4, NombreEmpleado4,
            CodigoRuta, DescripcionRuta, FechaUltimaModificacion, HoraUltimaModificacion,
            EstatusEnvio, PesoTotalEnvio, NumeroPlaca, Dato1, Dato2,
            EsVigente, HashDiff, RunId
        )
        VALUES (
            origen.NumeroEnvio, origen.UsuarioGenero, origen.PantallaGeneracion, origen.FechaGeneracion, origen.HoraGeneracion,
            origen.NumeroCamion, origen.CapacidadCamionKgs, origen.PropietarioCamion, origen.NumeroMotorista, origen.NombreMotorista,
            origen.NumeroEmpleado1, origen.NombreEmpleado1, origen.NumeroEmpleado2, origen.NombreEmpleado2,
            origen.NumeroEmpleado3, origen.NombreEmpleado3, origen.NumeroEmpleado4, origen.NombreEmpleado4,
            origen.CodigoRuta, origen.DescripcionRuta, origen.FechaUltimaModificacion, origen.HoraUltimaModificacion,
            origen.EstatusEnvio, origen.PesoTotalEnvio, origen.NumeroPlaca, origen.Dato1, origen.Dato2,
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

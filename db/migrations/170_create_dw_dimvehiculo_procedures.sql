-- 170: merge Silver -> Gold para dimVehiculo. SCD Tipo 1 (sobrescribe).
-- Reutiliza el HashDiff de [int].dimVehiculo. ProveedorKey/PaisKey via LEFT
-- JOIN (codigos unicos en dw, no duplica filas); tambien se actualiza cuando
-- solo cambia la llave, para completar llaves que llegan despues (proveedor
-- o pais dado de alta mas tarde). Correr despues de dimProveedor y dimPais.

CREATE OR ALTER PROCEDURE dw.usp_MergeDimVehiculo
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].dimVehiculo);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH Origen AS (
        SELECT
            v.CMCARR  AS CodigoVehiculo,
            v.CMID    AS TipoRegistro,
            v.CMCDES  AS MarcaModelo,
            v.CMXDES  AS Placa,
            v.CMADR6  AS TipoVehiculo,
            v.CMDATN  AS ClaseVehiculo,
            v.CMSHPC  AS Capacidad,
            v.CMADR1  AS EmpresaPropietaria,
            v.CMADR5  AS NumeroIdentidad,
            v.CMATTN  AS NombreMotorista,
            v.CMPHON  AS Telefono,
            v.CMADR2  AS Observaciones,
            p.ProveedorKey,
            v.CMVEND  AS CodigoProveedor,
            ps.PaisKey,
            v.CMCNTY  AS CodigoPais,
            v.CMSTCD  AS CodigoEstado,
            v.CMPSCD  AS CodigoPostal,
            v.CMPERR  AS CalificacionDesempeno,
            v.CMINVF  AS IndicadorFacturacion,
            v.CMFRCC  AS CodigoCargoFlete,
            v.CMLUSR  AS UsuarioModificacion,
            v.CMLDTE  AS FechaModificacion,
            v.CMLTME  AS HoraModificacion,
            v.EsVigente,
            v.HashDiff
        FROM [int].dimVehiculo v
        LEFT JOIN dw.dimProveedor p ON p.CodigoProveedor = v.CMVEND
        LEFT JOIN dw.dimPais ps     ON ps.CodigoPaisAlpha3 = v.CMCNTY
    )
    MERGE dw.dimVehiculo AS destino
        USING Origen AS origen
        ON destino.CodigoVehiculo = origen.CodigoVehiculo
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente <> origen.EsVigente
                      OR ISNULL(destino.ProveedorKey, -1) <> ISNULL(origen.ProveedorKey, -1)
                      OR ISNULL(destino.PaisKey, -1) <> ISNULL(origen.PaisKey, -1)) THEN
        UPDATE SET
            TipoRegistro          = origen.TipoRegistro,
            MarcaModelo           = origen.MarcaModelo,
            Placa                 = origen.Placa,
            TipoVehiculo          = origen.TipoVehiculo,
            ClaseVehiculo         = origen.ClaseVehiculo,
            Capacidad             = origen.Capacidad,
            EmpresaPropietaria    = origen.EmpresaPropietaria,
            NumeroIdentidad       = origen.NumeroIdentidad,
            NombreMotorista       = origen.NombreMotorista,
            Telefono              = origen.Telefono,
            Observaciones         = origen.Observaciones,
            ProveedorKey          = origen.ProveedorKey,
            CodigoProveedor       = origen.CodigoProveedor,
            PaisKey               = origen.PaisKey,
            CodigoPais            = origen.CodigoPais,
            CodigoEstado          = origen.CodigoEstado,
            CodigoPostal          = origen.CodigoPostal,
            CalificacionDesempeno = origen.CalificacionDesempeno,
            IndicadorFacturacion  = origen.IndicadorFacturacion,
            CodigoCargoFlete      = origen.CodigoCargoFlete,
            UsuarioModificacion   = origen.UsuarioModificacion,
            FechaModificacion     = origen.FechaModificacion,
            HoraModificacion      = origen.HoraModificacion,
            EsVigente             = origen.EsVigente,
            HashDiff              = origen.HashDiff,
            FechaCargaDw          = SYSDATETIME(),
            RunId                 = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (CodigoVehiculo, TipoRegistro, MarcaModelo, Placa, TipoVehiculo, ClaseVehiculo, Capacidad,
                EmpresaPropietaria, NumeroIdentidad, NombreMotorista, Telefono, Observaciones, ProveedorKey,
                CodigoProveedor, PaisKey, CodigoPais, CodigoEstado, CodigoPostal, CalificacionDesempeno,
                IndicadorFacturacion, CodigoCargoFlete, UsuarioModificacion, FechaModificacion, HoraModificacion,
                EsVigente, HashDiff, RunId)
        VALUES (origen.CodigoVehiculo, origen.TipoRegistro, origen.MarcaModelo, origen.Placa, origen.TipoVehiculo,
                origen.ClaseVehiculo, origen.Capacidad, origen.EmpresaPropietaria, origen.NumeroIdentidad,
                origen.NombreMotorista, origen.Telefono, origen.Observaciones, origen.ProveedorKey,
                origen.CodigoProveedor, origen.PaisKey, origen.CodigoPais, origen.CodigoEstado, origen.CodigoPostal,
                origen.CalificacionDesempeno, origen.IndicadorFacturacion, origen.CodigoCargoFlete,
                origen.UsuarioModificacion, origen.FechaModificacion, origen.HoraModificacion,
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

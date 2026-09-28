-- 178: Silver -> Gold para factGuiasRemision. REEMPLAZO POR RANGO, no MERGE (sin llave
-- unica, ver 175/176).
--   Incremental: @Desde = fecha de registro mas antigua entre las filas de [int] con
--     FechaCargaInt > @UltimoWatermark (lo que silver reemplazo desde el ultimo gold).
--     Se borra dw.FechaRegistro >= @Desde y se reinserta [int] desde esa fecha. Si no hay
--     filas nuevas en [int], no toca nada.
--   Reconciliar (o sin watermark): reemplaza todo dw desde [int] (TRUNCATE + INSERT) y
--     re-resuelve las llaves de dimension que hubieran quedado NULL por llegada tardia.
-- Devuelve el nuevo watermark = MAX(FechaCargaInt) de [int]. Compatible con SQL Server 2016.
-- Precision: FechaCargaInt es DATETIME2(7) (100 ns) pero el watermark vuelve de Python
-- truncado a microsegundos, y todas las filas de un reemplazo comparten el mismo
-- FechaCargaInt. Con un "> @UltimoWatermark" simple, el ultimo lote ya procesado volveria
-- a entrar completo (y gold reemplazaria todo). Por eso se compara contra
-- @UltimoWatermark + 1 microsegundo.

CREATE OR ALTER PROCEDURE dw.usp_MergeFactGuiasRemision
    @RunId            INT,
    @UltimoWatermark  DATETIME2(7) = NULL,
    @Reconciliar      BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @NuevoWatermark DATETIME2(7) = (SELECT MAX(FechaCargaInt) FROM [int].factGuiasRemision);
    DECLARE @Desde DATE;

    IF @Reconciliar = 1 OR @UltimoWatermark IS NULL
        SET @Desde = (SELECT MIN(D100F1) FROM [int].factGuiasRemision);
    ELSE
        SET @Desde = (SELECT MIN(D100F1) FROM [int].factGuiasRemision
                      WHERE FechaCargaInt >= DATEADD(MICROSECOND, 1, @UltimoWatermark));

    IF @Desde IS NULL
    BEGIN
        SELECT 0 AS FilasLeidas, 0 AS FilasInsertadas, 0 AS FilasActualizadas, 0 AS FilasIgnoradas,
               COALESCE(@NuevoWatermark, @UltimoWatermark) AS NuevoWatermark, 0 AS FilasEliminadas, CAST(NULL AS DATE) AS Desde;
        RETURN;
    END

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].factGuiasRemision WHERE D100F1 >= @Desde);

    DECLARE @FilasEliminadas INT;
    IF NOT EXISTS (SELECT 1 FROM dw.factGuiasRemision WHERE FechaRegistro < @Desde)
    BEGIN
        SET @FilasEliminadas = (SELECT COUNT(*) FROM dw.factGuiasRemision);
        TRUNCATE TABLE dw.factGuiasRemision;
    END
    ELSE
    BEGIN
        DELETE FROM dw.factGuiasRemision WHERE FechaRegistro >= @Desde;
        SET @FilasEliminadas = @@ROWCOUNT;
    END

    INSERT INTO dw.factGuiasRemision (
        EmpresaKey, ClienteKey, ProductoKey, VehiculoKey, MotivoTrasladoKey,
        NumeroEmpresa, CodigoOrigen, PrefijoGuia, CentroImpresion, Seccion, TipoDocumento, NumeroGuia,
        CodigoCAI, RangoAutorizadoInicio, RangoAutorizadoFin, FechaInicioAutorizacion, FechaFinAutorizacion,
        NumeroEnvio, CodigoMotivoTraslado, FechaEnvio, HoraEnvio, CodigoCamion, CodigoRemolque, NumeroManifiesto,
        NumeroCliente, RTNCliente, NumeroPedido, NumeroFactura, FechaFactura,
        CodigoProducto, Cantidad, PesoKilos, ValorNeto,
        Pantalla, Usuario, FechaRegistro, HoraRegistro, Estado, RunId)
    SELECT
        e.EmpresaKey, c.ClienteKey, p.ProductoKey, v.VehiculoKey, m.MotivoTrasladoKey,
        i.D100CI, i.D100OR, i.D100PF, i.D100GC, i.D100GS, i.D100GD, i.D100NG,
        i.D100NC, i.D100NI, i.D100NF, i.D100FI, i.D100FF,
        i.D100EN, i.D100MT, i.D100FV, i.D100HR, i.D100CM, i.D100RM, i.D100MF,
        i.D100CL, i.D100RC, i.D100PE, i.D100FC, i.D100FE,
        i.D100PR, i.D100CA, i.D100PK, i.D100VA,
        i.D100WS, i.D100US, i.D100F1, i.D100H1, i.D100ET, @RunId
    FROM [int].factGuiasRemision i
    LEFT JOIN dw.dimEmpresas       e ON e.CodigoEmpresa        = i.D100CI
    LEFT JOIN dw.dimCliente        c ON c.CodigoCliente        = i.D100CL
    LEFT JOIN dw.dimProducto       p ON p.CodigoProducto       = i.D100PR
    LEFT JOIN dw.dimVehiculo       v ON v.CodigoVehiculo       = i.D100CM
    LEFT JOIN dw.dimMotivoTraslado m ON m.CodigoMotivoTraslado = i.D100MT
    WHERE i.D100F1 >= @Desde;
    DECLARE @FilasInsertadas INT = @@ROWCOUNT;

    SELECT
        @FilasLeidas                     AS FilasLeidas,
        @FilasInsertadas                 AS FilasInsertadas,
        0                                AS FilasActualizadas,
        @FilasLeidas - @FilasInsertadas  AS FilasIgnoradas,
        @NuevoWatermark                  AS NuevoWatermark,
        @FilasEliminadas                 AS FilasEliminadas,
        @Desde                           AS Desde;
END
GO

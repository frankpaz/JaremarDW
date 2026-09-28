-- 184: Silver -> Gold para factPedidos. REEMPLAZO POR RANGO, no MERGE (sin llave unica, ver
-- 181/182), mismo esquema que factGuiasRemision (178):
--   Incremental: @Desde = fecha mas antigua entre las filas de [int] cargadas despues de
--     @UltimoWatermark; se borra dw.FechaCreacion >= @Desde y se reinserta [int] desde ahi. Sin
--     filas nuevas en [int], no toca nada.
--   Reconciliar (o sin watermark): reemplaza todo dw desde [int] y re-resuelve las llaves.
-- El watermark vuelve de Python truncado a microsegundos y todas las filas de un reemplazo
-- comparten FechaCargaInt: se compara contra @UltimoWatermark + 1 microsegundo (ver 178).
-- Devuelve el nuevo watermark = MAX(FechaCargaInt) de [int]. Compatible con SQL Server 2016.

CREATE OR ALTER PROCEDURE dw.usp_MergeFactPedidos
    @RunId            INT,
    @UltimoWatermark  DATETIME2(7) = NULL,
    @Reconciliar      BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @NuevoWatermark DATETIME2(7) = (SELECT MAX(FechaCargaInt) FROM [int].factPedidos);
    DECLARE @Desde DATE;

    IF @Reconciliar = 1 OR @UltimoWatermark IS NULL
        SET @Desde = (SELECT MIN(D02FEC) FROM [int].factPedidos);
    ELSE
        SET @Desde = (SELECT MIN(D02FEC) FROM [int].factPedidos
                      WHERE FechaCargaInt >= DATEADD(MICROSECOND, 1, @UltimoWatermark));

    IF @Desde IS NULL
    BEGIN
        SELECT 0 AS FilasLeidas, 0 AS FilasInsertadas, 0 AS FilasActualizadas, 0 AS FilasIgnoradas,
               COALESCE(@NuevoWatermark, @UltimoWatermark) AS NuevoWatermark, 0 AS FilasEliminadas, CAST(NULL AS DATE) AS Desde;
        RETURN;
    END

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].factPedidos WHERE D02FEC >= @Desde);

    DECLARE @FilasEliminadas INT;
    IF NOT EXISTS (SELECT 1 FROM dw.factPedidos WHERE FechaCreacion < @Desde)
    BEGIN
        SET @FilasEliminadas = (SELECT COUNT(*) FROM dw.factPedidos);
        TRUNCATE TABLE dw.factPedidos;
    END
    ELSE
    BEGIN
        DELETE FROM dw.factPedidos WHERE FechaCreacion >= @Desde;
        SET @FilasEliminadas = @@ROWCOUNT;
    END

    INSERT INTO dw.factPedidos (
        EmpresaKey, ClienteKey, ProductoKey, RutaKey,
        CodigoEmpresa, NumeroOrden, CodigoCliente, NumeroLinea, CodigoProducto, Cantidad, Peso,
        CodigoAlmacen, CodigoLocalidad, UnidadMedida, NumeroReferencia, NumeroConsolidacion,
        CodigoRuta, CodigoRuta1, CodigoRuta2, MarcaProceso, FechaCreacion, HoraCreacion, RunId)
    SELECT
        e.EmpresaKey, c.ClienteKey, p.ProductoKey, r.RutaKey,
        i.D02CIA, i.D02ORD, i.D02CLI, i.D02LIN, i.D02PRO, i.D02CAN, i.D02PES,
        i.D02ALM, i.D02LOC, i.D02UM, i.D02REF, i.D02CON,
        i.D02DSR, i.D02DSS, i.D02DST, i.D02MAR, i.D02FEC, i.D02HOR, @RunId
    FROM [int].factPedidos i
    LEFT JOIN dw.dimEmpresas e ON e.CodigoEmpresa  = i.D02CIA
    LEFT JOIN dw.dimCliente  c ON c.CodigoCliente  = i.D02CLI
    LEFT JOIN dw.dimProducto p ON p.CodigoProducto = i.D02PRO
    LEFT JOIN dw.dimRuta     r ON r.CodigoRuta     = i.D02DSR
    WHERE i.D02FEC >= @Desde;
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

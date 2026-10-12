-- 274: UbicacionKey (dw.dimUbicacion) en dw.factManifiestos.
-- Resuelve almacen + localidad del manifiesto (D02ALM + D02LOC = CodigoAlmacen +
-- CodigoLocalidad) contra dw.dimUbicacion (CodigoAlmacen + CodigoUbicacion).
-- Verificado (2026-10-12): cruzan todas las lineas salvo 1 (almacen JND, ubicacion 110,
-- que no existe en ILM) y ninguna apunta a una ubicacion dada de baja.
-- Llegada tardia: gold reemplaza su ventana; la reconciliacion semanal todo el historico.
-- Esta migracion NO rellena las filas que ya existen (~2,8 M; migrate.py aplica todo en
-- una transaccion): el relleno inicial se hace en lotes aparte (2026-10-12). En un ambiente
-- nuevo lo hace la reconciliacion de manifiestos. dimUbicacion debe correr antes
-- (run_manifiestos.py). Compatible con SQL Server 2016.

IF COL_LENGTH('dw.factManifiestos', 'UbicacionKey') IS NULL
    ALTER TABLE dw.factManifiestos ADD UbicacionKey INT NULL
        CONSTRAINT FK_dw_factManifiestos_dimUbicacion REFERENCES dw.dimUbicacion(UbicacionKey);
GO

CREATE OR ALTER PROCEDURE dw.usp_MergeFactManifiestos
    @RunId            INT,
    @UltimoWatermark  DATETIME2(7) = NULL,
    @Reconciliar      BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @NuevoWatermark DATETIME2(7) = (SELECT MAX(FechaCargaInt) FROM [int].factManifiestos);
    DECLARE @Desde DATE;

    IF @Reconciliar = 1 OR @UltimoWatermark IS NULL
        SET @Desde = (SELECT MIN(D02FEC) FROM [int].factManifiestos);
    ELSE
        SET @Desde = (SELECT MIN(D02FEC) FROM [int].factManifiestos
                      WHERE FechaCargaInt >= DATEADD(MICROSECOND, 1, @UltimoWatermark));

    IF @Desde IS NULL
    BEGIN
        SELECT 0 AS FilasLeidas, 0 AS FilasInsertadas, 0 AS FilasActualizadas, 0 AS FilasIgnoradas,
               COALESCE(@NuevoWatermark, @UltimoWatermark) AS NuevoWatermark, 0 AS FilasEliminadas, CAST(NULL AS DATE) AS Desde;
        RETURN;
    END

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM [int].factManifiestos WHERE D02FEC >= @Desde);

    DECLARE @FilasEliminadas INT;
    IF NOT EXISTS (SELECT 1 FROM dw.factManifiestos WHERE FechaCreacion < @Desde)
    BEGIN
        SET @FilasEliminadas = (SELECT COUNT(*) FROM dw.factManifiestos);
        TRUNCATE TABLE dw.factManifiestos;
    END
    ELSE
    BEGIN
        DELETE FROM dw.factManifiestos WHERE FechaCreacion >= @Desde;
        SET @FilasEliminadas = @@ROWCOUNT;
    END

    INSERT INTO dw.factManifiestos (
        EmpresaKey, ClienteKey, ProductoKey, RutaKey, AlmacenKey, UbicacionKey,
        CodigoEmpresa, NumeroOrden, CodigoCliente, NumeroLinea, CodigoProducto, Cantidad, Peso,
        CodigoAlmacen, CodigoLocalidad, UnidadMedida, NumeroReferencia, NumeroConsolidacion,
        CodigoRuta, CodigoRuta1, CodigoRuta2, MarcaProceso, FechaCreacion, HoraCreacion, RunId)
    SELECT
        e.EmpresaKey, c.ClienteKey, p.ProductoKey, r.RutaKey, a.AlmacenKey, u.UbicacionKey,
        i.D02CIA, i.D02ORD, i.D02CLI, i.D02LIN, i.D02PRO, i.D02CAN, i.D02PES,
        i.D02ALM, i.D02LOC, i.D02UM, i.D02REF, i.D02CON,
        i.D02DSR, i.D02DSS, i.D02DST, i.D02MAR, i.D02FEC, i.D02HOR, @RunId
    FROM [int].factManifiestos i
    LEFT JOIN dw.dimEmpresas e ON e.CodigoEmpresa  = i.D02CIA
    LEFT JOIN dw.dimCliente  c ON c.CodigoCliente  = i.D02CLI
    LEFT JOIN dw.dimProducto p ON p.CodigoProducto = i.D02PRO
    LEFT JOIN dw.dimRuta     r ON r.CodigoRuta     = i.D02DSR
    LEFT JOIN dw.dimAlmacen  a ON a.CodigoAlmacen  = i.D02ALM
    LEFT JOIN dw.dimUbicacion u ON u.CodigoAlmacen = i.D02ALM AND u.CodigoUbicacion = i.D02LOC
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

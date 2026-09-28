-- 185: renombra factPedidos -> factManifiestos (decision del usuario 2026-09-28: la tabla
-- PROLXUSRF.UNDIS002 no es de pedidos). SOLO cambian nombres; estructura, datos, historial de
-- corridas y watermarks se conservan. Las migraciones 181-184 quedan como historia (crean
-- factPedidos) y esta las renombra, asi que una base nueva queda igual que produccion.
--   Tablas stg/[int]/dw.factPedidos -> factManifiestos; columna dw PedidoKey -> ManifiestoKey.
--   Constraints e indices *_factPedidos_* -> *_factManifiestos_*.
--   SPs [int]/dw.usp_MergeFactPedidos -> usp_MergeFactManifiestos (mismo cuerpo).
--   dbo.EtlProcess: Pedidos / Pedidos_Silver / Pedidos_Gold -> Manifiestos*, dominio Manifiestos.
-- Idempotente. Compatible con SQL Server 2016.

-- Tablas
IF OBJECT_ID('stg.factPedidos') IS NOT NULL AND OBJECT_ID('stg.factManifiestos') IS NULL
    EXEC sp_rename 'stg.factPedidos', 'factManifiestos';
IF OBJECT_ID('int.factPedidos') IS NOT NULL AND OBJECT_ID('int.factManifiestos') IS NULL
    EXEC sp_rename 'int.factPedidos', 'factManifiestos';
IF OBJECT_ID('dw.factPedidos') IS NOT NULL AND OBJECT_ID('dw.factManifiestos') IS NULL
    EXEC sp_rename 'dw.factPedidos', 'factManifiestos';
IF COL_LENGTH('dw.factManifiestos', 'PedidoKey') IS NOT NULL
    EXEC sp_rename 'dw.factManifiestos.PedidoKey', 'ManifiestoKey', 'COLUMN';

-- Constraints (PK, FK, DEFAULT); renombrar la PK renombra tambien su indice
IF OBJECT_ID('stg.DF_factPedidos_FechaCargaStg') IS NOT NULL
    EXEC sp_rename 'stg.DF_factPedidos_FechaCargaStg', 'DF_factManifiestos_FechaCargaStg', 'OBJECT';
IF OBJECT_ID('int.DF_Int_factPedidos_FechaCargaInt') IS NOT NULL
    EXEC sp_rename 'int.DF_Int_factPedidos_FechaCargaInt', 'DF_Int_factManifiestos_FechaCargaInt', 'OBJECT';
IF OBJECT_ID('dw.DF_dw_factPedidos_FechaCargaDw') IS NOT NULL
    EXEC sp_rename 'dw.DF_dw_factPedidos_FechaCargaDw', 'DF_dw_factManifiestos_FechaCargaDw', 'OBJECT';
IF OBJECT_ID('dw.PK_dw_factPedidos') IS NOT NULL
    EXEC sp_rename 'dw.PK_dw_factPedidos', 'PK_dw_factManifiestos', 'OBJECT';
IF OBJECT_ID('dw.FK_dw_factPedidos_dimEmpresas') IS NOT NULL
    EXEC sp_rename 'dw.FK_dw_factPedidos_dimEmpresas', 'FK_dw_factManifiestos_dimEmpresas', 'OBJECT';
IF OBJECT_ID('dw.FK_dw_factPedidos_dimCliente') IS NOT NULL
    EXEC sp_rename 'dw.FK_dw_factPedidos_dimCliente', 'FK_dw_factManifiestos_dimCliente', 'OBJECT';
IF OBJECT_ID('dw.FK_dw_factPedidos_dimProducto') IS NOT NULL
    EXEC sp_rename 'dw.FK_dw_factPedidos_dimProducto', 'FK_dw_factManifiestos_dimProducto', 'OBJECT';
IF OBJECT_ID('dw.FK_dw_factPedidos_dimRuta') IS NOT NULL
    EXEC sp_rename 'dw.FK_dw_factPedidos_dimRuta', 'FK_dw_factManifiestos_dimRuta', 'OBJECT';

-- Indices
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('int.factManifiestos') AND name = 'CIX_Int_factPedidos_D02FEC')
    EXEC sp_rename 'int.factManifiestos.CIX_Int_factPedidos_D02FEC', 'CIX_Int_factManifiestos_D02FEC', 'INDEX';
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('int.factManifiestos') AND name = 'IX_Int_factPedidos_FechaCargaInt')
    EXEC sp_rename 'int.factManifiestos.IX_Int_factPedidos_FechaCargaInt', 'IX_Int_factManifiestos_FechaCargaInt', 'INDEX';
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dw.factManifiestos') AND name = 'CIX_dw_factPedidos_FechaCreacion')
    EXEC sp_rename 'dw.factManifiestos.CIX_dw_factPedidos_FechaCreacion', 'CIX_dw_factManifiestos_FechaCreacion', 'INDEX';
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dw.factManifiestos') AND name = 'IX_dw_factPedidos_Orden')
    EXEC sp_rename 'dw.factManifiestos.IX_dw_factPedidos_Orden', 'IX_dw_factManifiestos_Orden', 'INDEX';
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dw.factManifiestos') AND name = 'IX_dw_factPedidos_NumeroOrden')
    EXEC sp_rename 'dw.factManifiestos.IX_dw_factPedidos_NumeroOrden', 'IX_dw_factManifiestos_NumeroOrden', 'INDEX';

-- SPs viejos (se recrean abajo con el nombre nuevo)
IF OBJECT_ID('int.usp_MergeFactPedidos') IS NOT NULL DROP PROCEDURE [int].usp_MergeFactPedidos;
IF OBJECT_ID('dw.usp_MergeFactPedidos') IS NOT NULL DROP PROCEDURE dw.usp_MergeFactPedidos;

-- Framework de control: el historial de corridas y el watermark cuelgan de ProcesoId, se conservan
UPDATE dbo.EtlProcess
SET ProcesoNombre = REPLACE(ProcesoNombre, 'Pedidos', 'Manifiestos'),
    Dominio       = 'Manifiestos',
    TablaOrigen   = REPLACE(TablaOrigen, 'factPedidos', 'factManifiestos'),
    TablaDestino  = REPLACE(TablaDestino, 'factPedidos', 'factManifiestos'),
    FechaModificacion = SYSDATETIME()
WHERE ProcesoNombre IN ('Pedidos', 'Pedidos_Silver', 'Pedidos_Gold')
  AND NOT EXISTS (SELECT 1 FROM dbo.EtlProcess WHERE ProcesoNombre IN ('Manifiestos', 'Manifiestos_Silver', 'Manifiestos_Gold'));
GO

CREATE OR ALTER PROCEDURE [int].usp_MergeFactManifiestos
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.factManifiestos);
    IF @FilasLeidas = 0
        THROW 50001, 'stg.factManifiestos esta vacio: no se reemplaza [int] (revisar el extract).', 1;

    CREATE TABLE #Normalizado (
        D02CIA DECIMAL(2,0) NOT NULL, D02ORD DECIMAL(8,0) NOT NULL, D02CLI DECIMAL(8,0) NULL, D02LIN DECIMAL(4,0) NULL,
        D02PRO NVARCHAR(35) NULL, D02CAN DECIMAL(11,3) NULL, D02PES DECIMAL(12,2) NULL, D02ALM NVARCHAR(3) NULL,
        D02LOC NVARCHAR(10) NULL, D02UM NVARCHAR(2) NULL, D02REF NVARCHAR(15) NULL, D02CON DECIMAL(6,0) NULL,
        D02DSR NVARCHAR(6) NULL, D02DSS NVARCHAR(6) NULL, D02DST NVARCHAR(6) NULL, D02MAR NVARCHAR(1) NULL,
        D02FEC DATE NULL, D02HOR TIME(0) NULL
    );

    ;WITH StgFechas AS (
        SELECT s.*,
               TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(NULLIF(s.D02FEC, 0) AS BIGINT))) AS FechaFEC
        FROM stg.factManifiestos s
    )
    INSERT INTO #Normalizado
    SELECT
        s.D02CIA,
        s.D02ORD,
        NULLIF(s.D02CLI, 0),
        s.D02LIN,
        NULLIF(LTRIM(RTRIM(s.D02PRO)), ''),
        s.D02CAN,
        s.D02PES,
        NULLIF(LTRIM(RTRIM(s.D02ALM)), ''),
        NULLIF(LTRIM(RTRIM(s.D02LOC)), ''),
        NULLIF(LTRIM(RTRIM(s.D02UM)), ''),
        NULLIF(LTRIM(RTRIM(s.D02REF)), ''),
        NULLIF(s.D02CON, 0),
        NULLIF(LTRIM(RTRIM(s.D02DSR)), ''),
        NULLIF(LTRIM(RTRIM(s.D02DSS)), ''),
        NULLIF(LTRIM(RTRIM(s.D02DST)), ''),
        NULLIF(LTRIM(RTRIM(s.D02MAR)), ''),
        s.FechaFEC,
        CASE WHEN s.FechaFEC IS NOT NULL AND s.D02HOR <> 0 THEN
            TRY_CONVERT(TIME(0), STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(8), CAST(s.D02HOR AS BIGINT)), 6), 3, 0, ':'), 6, 0, ':'))
        END
    FROM StgFechas s
    WHERE s.D02CIA IS NOT NULL AND s.D02ORD IS NOT NULL;

    DECLARE @Desde DATE = (SELECT MIN(D02FEC) FROM #Normalizado);
    IF @Desde IS NULL
        THROW 50002, 'Ninguna fila de stg.factManifiestos tiene fecha de la orden (D02FEC) valida.', 1;

    DECLARE @FilasEliminadas INT;
    IF NOT EXISTS (SELECT 1 FROM [int].factManifiestos WHERE D02FEC < @Desde)
    BEGIN
        SET @FilasEliminadas = (SELECT COUNT(*) FROM [int].factManifiestos);
        TRUNCATE TABLE [int].factManifiestos;
    END
    ELSE
    BEGIN
        DELETE FROM [int].factManifiestos WHERE D02FEC >= @Desde;
        SET @FilasEliminadas = @@ROWCOUNT;
    END

    INSERT INTO [int].factManifiestos (
        D02CIA, D02ORD, D02CLI, D02LIN, D02PRO, D02CAN, D02PES, D02ALM, D02LOC, D02UM, D02REF, D02CON,
        D02DSR, D02DSS, D02DST, D02MAR, D02FEC, D02HOR, RunId)
    SELECT
        D02CIA, D02ORD, D02CLI, D02LIN, D02PRO, D02CAN, D02PES, D02ALM, D02LOC, D02UM, D02REF, D02CON,
        D02DSR, D02DSS, D02DST, D02MAR, D02FEC, D02HOR, @RunId
    FROM #Normalizado
    WHERE D02FEC IS NOT NULL;
    DECLARE @FilasInsertadas INT = @@ROWCOUNT;

    SELECT
        @FilasLeidas                     AS FilasLeidas,
        @FilasInsertadas                 AS FilasInsertadas,
        0                                AS FilasActualizadas,
        @FilasLeidas - @FilasInsertadas  AS FilasIgnoradas,
        @FilasEliminadas                 AS FilasEliminadas,
        @Desde                           AS Desde;
END
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
        EmpresaKey, ClienteKey, ProductoKey, RutaKey,
        CodigoEmpresa, NumeroOrden, CodigoCliente, NumeroLinea, CodigoProducto, Cantidad, Peso,
        CodigoAlmacen, CodigoLocalidad, UnidadMedida, NumeroReferencia, NumeroConsolidacion,
        CodigoRuta, CodigoRuta1, CodigoRuta2, MarcaProceso, FechaCreacion, HoraCreacion, RunId)
    SELECT
        e.EmpresaKey, c.ClienteKey, p.ProductoKey, r.RutaKey,
        i.D02CIA, i.D02ORD, i.D02CLI, i.D02LIN, i.D02PRO, i.D02CAN, i.D02PES,
        i.D02ALM, i.D02LOC, i.D02UM, i.D02REF, i.D02CON,
        i.D02DSR, i.D02DSS, i.D02DST, i.D02MAR, i.D02FEC, i.D02HOR, @RunId
    FROM [int].factManifiestos i
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

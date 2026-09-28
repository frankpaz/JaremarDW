-- 176: Bronze -> Silver para factGuiasRemision. REEMPLAZO POR VENTANA, no MERGE
-- (el origen no tiene llave unica, ver 175): borra de [int] todo D100F1 >= la fecha
-- de registro mas antigua de stg e inserta stg completo. stg trae siempre la ventana
-- entera del extract (30 dias hacia atras del watermark, o desde 2025 al reconciliar),
-- asi que el resultado es fiel al origen en ese rango, incluidas anulaciones y borrados.
-- Si el rango cubre todo [int] se usa TRUNCATE (carga inicial / reconciliacion).
-- Aborta si stg esta vacio: una ventana de 30 dias sin guias no es normal y borraria
-- datos buenos. Las filas sin fecha de registro valida se ignoran (no se pueden ubicar
-- en ninguna ventana). Compatible con SQL Server 2016.

CREATE OR ALTER PROCEDURE [int].usp_MergeFactGuiasRemision
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.factGuiasRemision);
    IF @FilasLeidas = 0
        THROW 50001, 'stg.factGuiasRemision esta vacio: no se reemplaza [int] (revisar el extract).', 1;

    CREATE TABLE #Normalizado (
        D100CI INT NOT NULL, D100OR INT NULL, D100PF NVARCHAR(2) NULL, D100GC INT NULL, D100GS INT NULL,
        D100GD INT NULL, D100NG INT NOT NULL, D100NC NVARCHAR(40) NULL, D100NI INT NULL, D100NF INT NULL,
        D100FI DATE NULL, D100FF DATE NULL, D100EN INT NULL, D100MT INT NULL, D100FV DATE NULL, D100HR TIME(0) NULL,
        D100CM NVARCHAR(6) NULL, D100RM NVARCHAR(6) NULL, D100MF INT NULL, D100CL INT NULL, D100RC NVARCHAR(16) NULL,
        D100PE INT NULL, D100FC INT NULL, D100FE DATE NULL, D100PR NVARCHAR(35) NULL,
        D100CA DECIMAL(15,3) NULL, D100PK DECIMAL(15,2) NULL, D100VA DECIMAL(15,2) NULL,
        D100WS NVARCHAR(10) NULL, D100US NVARCHAR(10) NULL, D100F1 DATE NULL, D100H1 TIME(0) NULL, D100ET NVARCHAR(6) NULL
    );

    ;WITH StgFechas AS (
        SELECT s.*,
               TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(NULLIF(s.D100FI, 0) AS BIGINT))) AS FechaFI,
               TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(NULLIF(s.D100FF, 0) AS BIGINT))) AS FechaFF,
               TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(NULLIF(s.D100FV, 0) AS BIGINT))) AS FechaFV,
               TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(NULLIF(s.D100FE, 0) AS BIGINT))) AS FechaFE,
               TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(NULLIF(s.D100F1, 0) AS BIGINT))) AS FechaF1
        FROM stg.factGuiasRemision s
    )
    INSERT INTO #Normalizado
    SELECT
        CAST(s.D100CI AS INT),
        CAST(NULLIF(s.D100OR, 0) AS INT),
        NULLIF(RTRIM(s.D100PF), ''),
        CAST(s.D100GC AS INT),
        CAST(s.D100GS AS INT),
        CAST(s.D100GD AS INT),
        CAST(s.D100NG AS INT),
        NULLIF(RTRIM(s.D100NC), ''),
        CAST(s.D100NI AS INT),
        CAST(s.D100NF AS INT),
        s.FechaFI,
        s.FechaFF,
        CAST(NULLIF(s.D100EN, 0) AS INT),
        CAST(s.D100MT AS INT),
        s.FechaFV,
        CASE WHEN s.FechaFV IS NOT NULL THEN
            TRY_CONVERT(TIME(0), STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(8), CAST(s.D100HR AS BIGINT)), 6), 3, 0, ':'), 6, 0, ':'))
        END,
        NULLIF(RTRIM(s.D100CM), ''),
        NULLIF(RTRIM(s.D100RM), ''),
        CAST(NULLIF(s.D100MF, 0) AS INT),
        CAST(NULLIF(s.D100CL, 0) AS INT),
        NULLIF(RTRIM(s.D100RC), ''),
        CAST(NULLIF(s.D100PE, 0) AS INT),
        CAST(NULLIF(s.D100FC, 0) AS INT),
        s.FechaFE,
        NULLIF(RTRIM(s.D100PR), ''),
        s.D100CA,
        s.D100PK,
        s.D100VA,
        NULLIF(RTRIM(s.D100WS), ''),
        NULLIF(RTRIM(s.D100US), ''),
        s.FechaF1,
        CASE WHEN s.FechaF1 IS NOT NULL THEN
            TRY_CONVERT(TIME(0), STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(8), CAST(s.D100H1 AS BIGINT)), 6), 3, 0, ':'), 6, 0, ':'))
        END,
        NULLIF(RTRIM(s.D100ET), '')
    FROM StgFechas s
    WHERE s.D100CI IS NOT NULL AND s.D100NG IS NOT NULL;

    DECLARE @Desde DATE = (SELECT MIN(D100F1) FROM #Normalizado);
    IF @Desde IS NULL
        THROW 50002, 'Ninguna fila de stg.factGuiasRemision tiene fecha de registro (D100F1) valida.', 1;

    DECLARE @FilasEliminadas INT;
    IF NOT EXISTS (SELECT 1 FROM [int].factGuiasRemision WHERE D100F1 < @Desde)
    BEGIN
        SET @FilasEliminadas = (SELECT COUNT(*) FROM [int].factGuiasRemision);
        TRUNCATE TABLE [int].factGuiasRemision;
    END
    ELSE
    BEGIN
        DELETE FROM [int].factGuiasRemision WHERE D100F1 >= @Desde;
        SET @FilasEliminadas = @@ROWCOUNT;
    END

    INSERT INTO [int].factGuiasRemision (
        D100CI, D100OR, D100PF, D100GC, D100GS, D100GD, D100NG, D100NC, D100NI, D100NF, D100FI, D100FF,
        D100EN, D100MT, D100FV, D100HR, D100CM, D100RM, D100MF, D100CL, D100RC, D100PE, D100FC, D100FE,
        D100PR, D100CA, D100PK, D100VA, D100WS, D100US, D100F1, D100H1, D100ET, RunId)
    SELECT
        D100CI, D100OR, D100PF, D100GC, D100GS, D100GD, D100NG, D100NC, D100NI, D100NF, D100FI, D100FF,
        D100EN, D100MT, D100FV, D100HR, D100CM, D100RM, D100MF, D100CL, D100RC, D100PE, D100FC, D100FE,
        D100PR, D100CA, D100PK, D100VA, D100WS, D100US, D100F1, D100H1, D100ET, @RunId
    FROM #Normalizado
    WHERE D100F1 IS NOT NULL;
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

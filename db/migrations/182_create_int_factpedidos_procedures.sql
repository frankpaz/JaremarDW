-- 182: Bronze -> Silver para factPedidos. REEMPLAZO POR VENTANA, no MERGE (sin llave unica,
-- ver 181), mismo esquema que factGuiasRemision (176): borra de [int] todo D02FEC >= la fecha
-- mas antigua de stg e inserta stg completo; TRUNCATE si el rango cubre todo [int]. Aborta si
-- stg esta vacio (borraria datos buenos). Las filas sin fecha valida se ignoran.
-- Compatible con SQL Server 2016.

CREATE OR ALTER PROCEDURE [int].usp_MergeFactPedidos
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.factPedidos);
    IF @FilasLeidas = 0
        THROW 50001, 'stg.factPedidos esta vacio: no se reemplaza [int] (revisar el extract).', 1;

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
        FROM stg.factPedidos s
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
        THROW 50002, 'Ninguna fila de stg.factPedidos tiene fecha de la orden (D02FEC) valida.', 1;

    DECLARE @FilasEliminadas INT;
    IF NOT EXISTS (SELECT 1 FROM [int].factPedidos WHERE D02FEC < @Desde)
    BEGIN
        SET @FilasEliminadas = (SELECT COUNT(*) FROM [int].factPedidos);
        TRUNCATE TABLE [int].factPedidos;
    END
    ELSE
    BEGIN
        DELETE FROM [int].factPedidos WHERE D02FEC >= @Desde;
        SET @FilasEliminadas = @@ROWCOUNT;
    END

    INSERT INTO [int].factPedidos (
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

-- 254: merge Bronze -> Silver de factVentas con carga incremental por huella (estructura en la 253).
-- stg ya no trae una ventana de fechas: trae todas las lineas de los dias de factura (ILDATE) que no
-- cuadraron con el AS400 (stg.factVentas_Periodos) y los encabezados de esos mismos dias.
-- Pasos:
--   1. Cada linea toma su encabezado por compania + prefijo + documento + anio + tipo + fecha de
--      factura (SIINVD = ILDATE). Si no lo encuentra (no deberia pasar: el extract trae los
--      encabezados de los mismos dias), queda sin datos de encabezado y con HuellaOrigen NULL, para
--      que su dia no cuadre y se vuelva a traer en la corrida siguiente.
--   2. MERGE por compania + prefijo + documento + anio + tipo + linea + fecha de factura
--      (PeriodoOrigen), solo contra las filas de [int] de los dias traidos: inserta, actualiza si
--      cambia el HashDiff o la huella, y da de baja (EsVigente = 0, nunca borra) las lineas vigentes
--      que ya no estan en el AS400.
--   3. Horizonte de purga: el AS400 purga las ventas de mas de ~4 meses. Nunca se da de baja en dias
--      anteriores a hoy - @DiasHorizonteBajas (default 90): lo que el AS400 purga queda vigente en
--      [int], que pasa a ser la unica copia.
-- Resguardo: si daria de baja mas de @MaxBajas lineas, aborta sin tocar nada.
-- El HashDiff se calcula sobre las mismas 51 columnas y en el mismo orden que la 105, para que las
-- filas existentes no se marquen como cambiadas solo por el cambio de procedimiento.
-- Compatible con SQL Server 2016.

CREATE OR ALTER PROCEDURE [int].usp_MergeFactVentas
    @RunId               INT,
    @MaxBajas            INT = 200,
    @DiasHorizonteBajas  INT = 90
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.factVentasLineas);
    DECLARE @Horizonte DECIMAL(8,0) = CONVERT(DECIMAL(8,0), CONVERT(CHAR(8),
        DATEADD(DAY, -@DiasHorizonteBajas, CAST(GETDATE() AS DATE)), 112));

    -- 1. Encabezados de stg, uno por llave ------------------------------------------------------
    SELECT e.SICOMP, e.IHDPFX, e.IHDOCN, e.IHDYR, e.IHDTYP, e.SIINVD,
           e.SICURR, e.SICNFC, e.SIGCNV, e.SITERM, e.SICARR, e.SIROUT, e.IHENDT, e.IHENTM, e.IHENUS
    INTO #Enc
    FROM (
        SELECT h.*, ROW_NUMBER() OVER (PARTITION BY h.SICOMP, h.IHDPFX, h.IHDOCN, h.IHDYR, h.IHDTYP, h.SIINVD
                                       ORDER BY h.IHENDT DESC, h.IHENTM DESC) AS rn
        FROM stg.factVentasEncabezados h
        WHERE h.SICOMP IS NOT NULL
    ) e
    WHERE e.rn = 1;

    CREATE UNIQUE CLUSTERED INDEX IX_Enc ON #Enc (SICOMP, IHDPFX, IHDOCN, IHDYR, IHDTYP, SIINVD);

    -- 2. Lineas de stg, una por llave, con su encabezado ------------------------------------------
    ;WITH Lin AS (
        SELECT l.*,
               ROW_NUMBER() OVER (PARTITION BY l.ILCOMP, l.ILDPFX, l.ILDOCN, l.ILDYR, l.ILDTYP, l.ILLINE, l.ILDATE
                                  ORDER BY l.ILSEQ DESC) AS rn,
               COUNT(*) OVER (PARTITION BY l.ILCOMP, l.ILDPFX, l.ILDOCN, l.ILDYR, l.ILDTYP, l.ILLINE, l.ILDATE) AS Repeticiones,
               SUM(CAST(l.HUELLA AS DECIMAL(30,0))) OVER (PARTITION BY l.ILCOMP, l.ILDPFX, l.ILDOCN, l.ILDYR, l.ILDTYP, l.ILLINE, l.ILDATE) AS HuellaLinea
        FROM stg.factVentasLineas l
        WHERE l.ILCOMP IS NOT NULL
    ),
    LinConEncabezado AS (
        SELECT
            l.ILCOMP, l.ILDPFX, l.ILDOCN, l.ILDYR, l.ILDTYP, l.ILLINE, l.ILSEQ, l.ILINVN, l.ILORD, l.ILDATE,
            l.ILSDTE, l.ILPROD, l.ILCUST, l.ILCUSB, l.ILWHS, l.ILLTYP, l.ILOCLS, l.ILQTY, l.ILQINS, l.ILNET,
            l.ILNETS, l.ILLIST, l.ILBLST, l.ILEXTA, l.ILREV, l.ILPCST, l.ILUM, l.ILSLUM, l.ILCWUM, l.ILTR01,
            l.ILTA01, l.ILTR02, l.ILTA02, l.ILSAL1, l.ILSAL3, l.ILCCOM, l.ILCPO, l.ILCONS, l.ILNPSC, l.ILLPSC,
            l.ILPFAC, l.ILPKGG,
            h.SICURR, h.SICNFC, h.SIGCNV, h.SITERM, h.SICARR, h.SIROUT, h.IHENDT, h.IHENTM, h.IHENUS,
            l.ILDATE AS PeriodoOrigen,
            l.Repeticiones,
            CASE WHEN h.SICOMP IS NULL THEN NULL ELSE l.HuellaLinea END AS HuellaOrigen,
            CASE WHEN h.SICOMP IS NULL THEN 1 ELSE 0 END AS SinEncabezado
        FROM Lin l
        LEFT JOIN #Enc h
               ON h.SICOMP = l.ILCOMP AND h.IHDPFX = l.ILDPFX AND h.IHDOCN = l.ILDOCN
              AND h.IHDYR = l.ILDYR AND h.IHDTYP = l.ILDTYP AND h.SIINVD = l.ILDATE
        WHERE l.rn = 1
    ),
    LinNormalizada AS (
        SELECT
            ILCOMP,
            ILDPFX,
            ILDOCN,
            ILDYR,
            ILDTYP,
            ILLINE,
            ILSEQ,
            ILINVN,
            ILORD,
            TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(ILDATE AS BIGINT))) AS ILDATE,
            TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(ILSDTE AS BIGINT))) AS ILSDTE,
            NULLIF(RTRIM(ILPROD), '') AS ILPROD,
            ILCUST,
            ILCUSB,
            NULLIF(RTRIM(ILWHS), '') AS ILWHS,
            NULLIF(RTRIM(ILLTYP), '') AS ILLTYP,
            ILOCLS,
            ILQTY,
            ILQINS,
            ILNET,
            ILNETS,
            ILLIST,
            ILBLST,
            ILEXTA,
            ILREV,
            ILPCST,
            NULLIF(RTRIM(ILUM), '') AS ILUM,
            NULLIF(RTRIM(ILSLUM), '') AS ILSLUM,
            NULLIF(RTRIM(ILCWUM), '') AS ILCWUM,
            NULLIF(RTRIM(ILTR01), '') AS ILTR01,
            ILTA01,
            NULLIF(RTRIM(ILTR02), '') AS ILTR02,
            ILTA02,
            ILSAL1,
            ILSAL3,
            NULLIF(RTRIM(ILCCOM), '') AS ILCCOM,
            NULLIF(RTRIM(ILCPO), '') AS ILCPO,
            ILCONS,
            NULLIF(RTRIM(ILNPSC), '') AS ILNPSC,
            NULLIF(RTRIM(ILLPSC), '') AS ILLPSC,
            NULLIF(RTRIM(ILPFAC), '') AS ILPFAC,
            ILPKGG,
            NULLIF(RTRIM(SICURR), '') AS SICURR,
            SICNFC,
            SIGCNV,
            NULLIF(RTRIM(SITERM), '') AS SITERM,
            NULLIF(RTRIM(SICARR), '') AS SICARR,
            NULLIF(RTRIM(SIROUT), '') AS SIROUT,
            TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(IHENDT AS BIGINT))) AS IHENDT,
            TRY_CONVERT(TIME(0), STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(6), CAST(IHENTM AS BIGINT)), 6), 3, 0, ':'), 6, 0, ':')) AS IHENTM,
            NULLIF(RTRIM(IHENUS), '') AS IHENUS,
            PeriodoOrigen,
            Repeticiones,
            HuellaOrigen,
            SinEncabezado
        FROM LinConEncabezado
    )
    SELECT n.*,
           HASHBYTES('SHA2_256', (
               SELECT n.ILCOMP, n.ILDPFX, n.ILDOCN, n.ILDYR, n.ILDTYP, n.ILLINE, n.ILSEQ, n.ILINVN, n.ILORD,
                      n.ILDATE, n.ILSDTE, n.ILPROD, n.ILCUST, n.ILCUSB, n.ILWHS, n.ILLTYP, n.ILOCLS, n.ILQTY,
                      n.ILQINS, n.ILNET, n.ILNETS, n.ILLIST, n.ILBLST, n.ILEXTA, n.ILREV, n.ILPCST, n.ILUM,
                      n.ILSLUM, n.ILCWUM, n.ILTR01, n.ILTA01, n.ILTR02, n.ILTA02, n.ILSAL1, n.ILSAL3, n.ILCCOM,
                      n.ILCPO, n.ILCONS, n.ILNPSC, n.ILLPSC, n.ILPFAC, n.ILPKGG, n.SICURR, n.SICNFC, n.SIGCNV,
                      n.SITERM, n.SICARR, n.SIROUT, n.IHENDT, n.IHENTM, n.IHENUS
               FOR XML RAW, BINARY BASE64)) AS HashDiff
    INTO #Lin
    FROM LinNormalizada n;

    CREATE UNIQUE CLUSTERED INDEX IX_Lin ON #Lin (ILCOMP, ILDPFX, ILDOCN, ILDYR, ILDTYP, ILLINE, PeriodoOrigen);

    DECLARE @SinEncabezado INT = (SELECT COUNT(*) FROM #Lin WHERE SinEncabezado = 1);

    -- 3. Resguardo de bajas (solo dias traidos y dentro del horizonte) ---------------------------
    SELECT p.Periodo INTO #PeriodosBaja
    FROM stg.factVentas_Periodos p
    WHERE p.Periodo >= @Horizonte;

    DECLARE @Bajas INT = (
        SELECT COUNT(*) FROM [int].factVentas d
        WHERE d.EsVigente = 1
          AND d.PeriodoOrigen IN (SELECT Periodo FROM #PeriodosBaja)
          AND NOT EXISTS (SELECT 1 FROM #Lin o
                          WHERE o.ILCOMP = d.ILCOMP AND o.ILDPFX = d.ILDPFX AND o.ILDOCN = d.ILDOCN
                            AND o.ILDYR = d.ILDYR AND o.ILDTYP = d.ILDTYP AND o.ILLINE = d.ILLINE
                            AND o.PeriodoOrigen = d.PeriodoOrigen)
    );
    IF @Bajas > @MaxBajas
    BEGIN
        DECLARE @Msg NVARCHAR(400) = CONCAT(N'La corrida daria de baja ', @Bajas, N' lineas (limite ', @MaxBajas,
            N'): se aborta sin cambios. Revisar el extract; si las bajas son reales, correr silver con --max-bajas.');
        THROW 50003, @Msg, 1;
    END

    -- 4. MERGE, solo contra las filas de [int] de los dias traidos -------------------------------
    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL, EsVigente BIT NULL);

    ;WITH Destino AS (
        SELECT * FROM [int].factVentas
        WHERE PeriodoOrigen IN (SELECT p.Periodo FROM stg.factVentas_Periodos p)
    )
    MERGE Destino AS destino
        USING #Lin AS origen
        ON destino.ILCOMP = origen.ILCOMP AND destino.ILDPFX = origen.ILDPFX AND destino.ILDOCN = origen.ILDOCN
       AND destino.ILDYR = origen.ILDYR AND destino.ILDTYP = origen.ILDTYP AND destino.ILLINE = origen.ILLINE
       AND destino.PeriodoOrigen = origen.PeriodoOrigen
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff
                      OR destino.EsVigente = 0
                      OR destino.Repeticiones <> origen.Repeticiones
                      OR ISNULL(destino.HuellaOrigen, -1) <> ISNULL(origen.HuellaOrigen, -1)) THEN
        UPDATE SET
            ILSEQ = origen.ILSEQ,
            ILINVN = origen.ILINVN,
            ILORD = origen.ILORD,
            ILDATE = origen.ILDATE,
            ILSDTE = origen.ILSDTE,
            ILPROD = origen.ILPROD,
            ILCUST = origen.ILCUST,
            ILCUSB = origen.ILCUSB,
            ILWHS = origen.ILWHS,
            ILLTYP = origen.ILLTYP,
            ILOCLS = origen.ILOCLS,
            ILQTY = origen.ILQTY,
            ILQINS = origen.ILQINS,
            ILNET = origen.ILNET,
            ILNETS = origen.ILNETS,
            ILLIST = origen.ILLIST,
            ILBLST = origen.ILBLST,
            ILEXTA = origen.ILEXTA,
            ILREV = origen.ILREV,
            ILPCST = origen.ILPCST,
            ILUM = origen.ILUM,
            ILSLUM = origen.ILSLUM,
            ILCWUM = origen.ILCWUM,
            ILTR01 = origen.ILTR01,
            ILTA01 = origen.ILTA01,
            ILTR02 = origen.ILTR02,
            ILTA02 = origen.ILTA02,
            ILSAL1 = origen.ILSAL1,
            ILSAL3 = origen.ILSAL3,
            ILCCOM = origen.ILCCOM,
            ILCPO = origen.ILCPO,
            ILCONS = origen.ILCONS,
            ILNPSC = origen.ILNPSC,
            ILLPSC = origen.ILLPSC,
            ILPFAC = origen.ILPFAC,
            ILPKGG = origen.ILPKGG,
            SICURR = origen.SICURR,
            SICNFC = origen.SICNFC,
            SIGCNV = origen.SIGCNV,
            SITERM = origen.SITERM,
            SICARR = origen.SICARR,
            SIROUT = origen.SIROUT,
            IHENDT = origen.IHENDT,
            IHENTM = origen.IHENTM,
            IHENUS = origen.IHENUS,
            Repeticiones  = origen.Repeticiones,
            HuellaOrigen  = origen.HuellaOrigen,
            EsVigente     = 1,
            HashDiff      = origen.HashDiff,
            FechaCargaInt = SYSDATETIME(),
            RunId         = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (ILCOMP, ILDPFX, ILDOCN, ILDYR, ILDTYP, ILLINE, ILSEQ, ILINVN, ILORD, ILDATE, ILSDTE, ILPROD, ILCUST,
                ILCUSB, ILWHS, ILLTYP, ILOCLS, ILQTY, ILQINS, ILNET, ILNETS, ILLIST, ILBLST, ILEXTA, ILREV, ILPCST,
                ILUM, ILSLUM, ILCWUM, ILTR01, ILTA01, ILTR02, ILTA02, ILSAL1, ILSAL3, ILCCOM, ILCPO, ILCONS, ILNPSC,
                ILLPSC, ILPFAC, ILPKGG, SICURR, SICNFC, SIGCNV, SITERM, SICARR, SIROUT, IHENDT, IHENTM, IHENUS,
                PeriodoOrigen, Repeticiones, HuellaOrigen, HashDiff, RunId)
        VALUES (origen.ILCOMP, origen.ILDPFX, origen.ILDOCN, origen.ILDYR, origen.ILDTYP, origen.ILLINE, origen.ILSEQ,
                origen.ILINVN, origen.ILORD, origen.ILDATE, origen.ILSDTE, origen.ILPROD, origen.ILCUST, origen.ILCUSB,
                origen.ILWHS, origen.ILLTYP, origen.ILOCLS, origen.ILQTY, origen.ILQINS, origen.ILNET, origen.ILNETS,
                origen.ILLIST, origen.ILBLST, origen.ILEXTA, origen.ILREV, origen.ILPCST, origen.ILUM, origen.ILSLUM,
                origen.ILCWUM, origen.ILTR01, origen.ILTA01, origen.ILTR02, origen.ILTA02, origen.ILSAL1, origen.ILSAL3,
                origen.ILCCOM, origen.ILCPO, origen.ILCONS, origen.ILNPSC, origen.ILLPSC, origen.ILPFAC, origen.ILPKGG,
                origen.SICURR, origen.SICNFC, origen.SIGCNV, origen.SITERM, origen.SICARR, origen.SIROUT, origen.IHENDT,
                origen.IHENTM, origen.IHENUS, origen.PeriodoOrigen, origen.Repeticiones, origen.HuellaOrigen,
                origen.HashDiff, @RunId)
    WHEN NOT MATCHED BY SOURCE AND destino.EsVigente = 1
                              AND destino.PeriodoOrigen IN (SELECT Periodo FROM #PeriodosBaja) THEN
        UPDATE SET EsVigente = 0, FechaCargaInt = SYSDATETIME(), RunId = @RunId
    OUTPUT $action, inserted.EsVigente INTO #AccionesMerge;

    SELECT
        @FilasLeidas                                                                         AS FilasLeidas,
        ISNULL(SUM(CASE WHEN Accion = 'INSERT' THEN 1 ELSE 0 END), 0)                        AS FilasInsertadas,
        ISNULL(SUM(CASE WHEN Accion = 'UPDATE' AND EsVigente = 1 THEN 1 ELSE 0 END), 0)      AS FilasActualizadas,
        @FilasLeidas - ISNULL(SUM(CASE WHEN Accion = 'INSERT' THEN 1 ELSE 0 END), 0)
                      - ISNULL(SUM(CASE WHEN Accion = 'UPDATE' AND EsVigente = 1 THEN 1 ELSE 0 END), 0) AS FilasIgnoradas,
        ISNULL(SUM(CASE WHEN Accion = 'UPDATE' AND EsVigente = 0 THEN 1 ELSE 0 END), 0)      AS FilasDadasDeBaja,
        @SinEncabezado                                                                       AS LineasSinEncabezado
    FROM #AccionesMerge;
END
GO

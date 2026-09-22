-- 105: merge Bronze -> Silver para factVentas. Junta stg.factVentasLineas
-- (SIL, ILID='IL') con stg.factVentasEncabezados (SIH, SIID='IH') via
-- IL*=IH* (prefijo/documento/anio/tipo). Dedup por la llave compuesta,
-- tiebreak por ILSEQ DESC (los pocos duplicados observados son casos raros
-- del origen).
-- FASE 2 (2026-09-22): a partir de aqui la extraccion es INCREMENTAL por
-- ventana de IHENDT (fecha de creacion del encabezado, con margen de
-- seguridad -- ver extract_fact_ventas_encabezados.py), no FULL. Por eso
-- NO existe rama "WHEN NOT MATCHED BY SOURCE" -- stg ya no refleja el
-- origen completo en cada corrida, solo la ventana incremental, asi que dar
-- de baja (EsVigente=0) lo que no aparece en stg seria incorrecto (borraria
-- del dw todo lo que quedo fuera de la ventana de esta corrida). Solo se
-- hace INSERT (nuevo) / UPDATE (cambio de HashDiff) dentro de la ventana,
-- igual patron que los facts incrementales del dominio Solar. EsVigente
-- queda siempre en 1 para las filas de este fact (vestigial, se conserva la
-- columna por consistencia con el resto del esquema, no se usa para dar de
-- baja aqui).

CREATE OR ALTER PROCEDURE [int].usp_MergeFactVentas
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.factVentasLineas);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH StgDeduplicado AS (
        SELECT
            l."ILCOMP",
            l."ILDPFX",
            l."ILDOCN",
            l."ILDYR",
            l."ILDTYP",
            l."ILLINE",
            l."ILSEQ",
            l."ILINVN",
            l."ILORD",
            l."ILDATE",
            l."ILSDTE",
            l."ILPROD",
            l."ILCUST",
            l."ILCUSB",
            l."ILWHS",
            l."ILLTYP",
            l."ILOCLS",
            l."ILQTY",
            l."ILQINS",
            l."ILNET",
            l."ILNETS",
            l."ILLIST",
            l."ILBLST",
            l."ILEXTA",
            l."ILREV",
            l."ILPCST",
            l."ILUM",
            l."ILSLUM",
            l."ILCWUM",
            l."ILTR01",
            l."ILTA01",
            l."ILTR02",
            l."ILTA02",
            l."ILSAL1",
            l."ILSAL3",
            l."ILCCOM",
            l."ILCPO",
            l."ILCONS",
            l."ILNPSC",
            l."ILLPSC",
            l."ILPFAC",
            l."ILPKGG",
            h."SICURR",
            h."SICNFC",
            h."SIGCNV",
            h."SITERM",
            h."SICARR",
            h."SIROUT",
            h."IHENDT",
            h."IHENTM",
            h."IHENUS",
               ROW_NUMBER() OVER (PARTITION BY l."ILCOMP", l."ILDPFX", l."ILDOCN", l."ILDYR", l."ILDTYP", l."ILLINE" ORDER BY l."ILSEQ" DESC) AS rn
        FROM stg.factVentasLineas l
        LEFT JOIN stg.factVentasEncabezados h
            ON l."ILDPFX" = h."IHDPFX" AND l."ILDOCN" = h."IHDOCN" AND l."ILDYR" = h."IHDYR" AND l."ILDTYP" = h."IHDTYP"
        WHERE l."ILCOMP" IS NOT NULL
    ),
    StgNormalizado AS (
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
            NULLIF(RTRIM(IHENUS), '') AS IHENUS
        FROM StgDeduplicado
        WHERE rn = 1
    ),
    StgConHash AS (
        SELECT
            n.*,
            HASHBYTES('SHA2_256', (SELECT n.* FOR XML RAW, BINARY BASE64)) AS HashDiff
        FROM StgNormalizado n
    )
    MERGE [int].factVentas AS destino
        USING StgConHash AS origen
        ON destino.ILCOMP = origen.ILCOMP AND destino.ILDPFX = origen.ILDPFX AND destino.ILDOCN = origen.ILDOCN AND destino.ILDYR = origen.ILDYR AND destino.ILDTYP = origen.ILDTYP AND destino.ILLINE = origen.ILLINE
    WHEN MATCHED AND destino.HashDiff <> origen.HashDiff THEN
        UPDATE SET
            ILCOMP = origen.ILCOMP,
            ILDPFX = origen.ILDPFX,
            ILDOCN = origen.ILDOCN,
            ILDYR = origen.ILDYR,
            ILDTYP = origen.ILDTYP,
            ILLINE = origen.ILLINE,
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
            EsVigente     = 1,
            HashDiff      = origen.HashDiff,
            FechaCargaInt = SYSDATETIME(),
            RunId         = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (ILCOMP, ILDPFX, ILDOCN, ILDYR, ILDTYP, ILLINE, ILSEQ, ILINVN, ILORD, ILDATE, ILSDTE, ILPROD, ILCUST, ILCUSB, ILWHS, ILLTYP, ILOCLS, ILQTY, ILQINS, ILNET, ILNETS, ILLIST, ILBLST, ILEXTA, ILREV, ILPCST, ILUM, ILSLUM, ILCWUM, ILTR01, ILTA01, ILTR02, ILTA02, ILSAL1, ILSAL3, ILCCOM, ILCPO, ILCONS, ILNPSC, ILLPSC, ILPFAC, ILPKGG, SICURR, SICNFC, SIGCNV, SITERM, SICARR, SIROUT, IHENDT, IHENTM, IHENUS, HashDiff, RunId)
        VALUES (origen.ILCOMP, origen.ILDPFX, origen.ILDOCN, origen.ILDYR, origen.ILDTYP, origen.ILLINE, origen.ILSEQ, origen.ILINVN, origen.ILORD, origen.ILDATE, origen.ILSDTE, origen.ILPROD, origen.ILCUST, origen.ILCUSB, origen.ILWHS, origen.ILLTYP, origen.ILOCLS, origen.ILQTY, origen.ILQINS, origen.ILNET, origen.ILNETS, origen.ILLIST, origen.ILBLST, origen.ILEXTA, origen.ILREV, origen.ILPCST, origen.ILUM, origen.ILSLUM, origen.ILCWUM, origen.ILTR01, origen.ILTA01, origen.ILTR02, origen.ILTA02, origen.ILSAL1, origen.ILSAL3, origen.ILCCOM, origen.ILCPO, origen.ILCONS, origen.ILNPSC, origen.ILLPSC, origen.ILPFAC, origen.ILPKGG, origen.SICURR, origen.SICNFC, origen.SIGCNV, origen.SITERM, origen.SICARR, origen.SIROUT, origen.IHENDT, origen.IHENTM, origen.IHENUS, origen.HashDiff, @RunId)
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

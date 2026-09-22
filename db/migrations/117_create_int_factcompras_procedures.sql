-- 117: merge Bronze -> Silver para factCompras. Junta stg.factComprasLineas
-- (APL, PLID='PL') con stg.factComprasEncabezados (APH, APHID='PH') via
-- PL*=APH* (compania/prefijo/anio/secuencia). Puro incremental (INSERT
-- nuevo / UPDATE si cambia HashDiff), sin rama de baja logica -- stg solo
-- trae la ventana incremental de cada corrida, no el origen completo (ver
-- comentario en 116).

CREATE OR ALTER PROCEDURE [int].usp_MergeFactCompras
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.factComprasLineas);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH StgDeduplicado AS (
        SELECT
            l."PLCMPY",
            l."PLDCPX",
            l."PLDCYR",
            l."PLDCSQ",
            l."PLLINE",
            l."PLVNDR",
            l."PLINV",
            l."PLTYPE",
            l."PLGLDT",
            l."PLAMT",
            l."PLBAMT",
            l."PLDESC",
            l."PLUSER",
            l."PLEDTE",
            l."PLETIM",
            l."PLRESN",
            h."APHPND",
            h."APHBNK",
            h."APHCUR",
            h."APHOLD",
            h."AINVDT",
            h."ADUEDT",
            h."ADISCD",
            h."APCINA",
            h."APCAMP",
            h."APCOUT",
            h."APPORD",
            h."APTERM",
            h."APSTAT",
            h."APPAYS",
            h."PHHTRT",
            h."PHTXBA",
            h."APVNTX",
            h."APPAYT",
               ROW_NUMBER() OVER (PARTITION BY l."PLCMPY", l."PLDCPX", l."PLDCYR", l."PLDCSQ", l."PLLINE" ORDER BY l."PLEDTE" DESC, l."PLETIM" DESC) AS rn
        FROM stg.factComprasLineas l
        LEFT JOIN stg.factComprasEncabezados h
            ON l."PLCMPY" = h."APCMPY" AND l."PLDCPX" = h."PHDCPX" AND l."PLDCYR" = h."PHDCYR" AND l."PLDCSQ" = h."PHDCSQ"
        WHERE l."PLCMPY" IS NOT NULL
    ),
    StgNormalizado AS (
        SELECT
            PLCMPY,
            PLDCPX,
            PLDCYR,
            PLDCSQ,
            PLLINE,
            PLVNDR,
            NULLIF(RTRIM(PLINV), '') AS PLINV,
            NULLIF(RTRIM(PLTYPE), '') AS PLTYPE,
            TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(PLGLDT AS BIGINT))) AS PLGLDT,
            PLAMT,
            PLBAMT,
            NULLIF(RTRIM(PLDESC), '') AS PLDESC,
            NULLIF(RTRIM(PLUSER), '') AS PLUSER,
            TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(PLEDTE AS BIGINT))) AS PLEDTE,
            TRY_CONVERT(TIME(0), STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(6), CAST(PLETIM AS BIGINT)), 6), 3, 0, ':'), 6, 0, ':')) AS PLETIM,
            NULLIF(RTRIM(PLRESN), '') AS PLRESN,
            APHPND,
            NULLIF(RTRIM(APHBNK), '') AS APHBNK,
            NULLIF(RTRIM(APHCUR), '') AS APHCUR,
            NULLIF(RTRIM(APHOLD), '') AS APHOLD,
            TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(AINVDT AS BIGINT))) AS AINVDT,
            TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(ADUEDT AS BIGINT))) AS ADUEDT,
            TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(ADISCD AS BIGINT))) AS ADISCD,
            APCINA,
            APCAMP,
            APCOUT,
            APPORD,
            NULLIF(RTRIM(APTERM), '') AS APTERM,
            NULLIF(RTRIM(APSTAT), '') AS APSTAT,
            NULLIF(RTRIM(APPAYS), '') AS APPAYS,
            PHHTRT,
            PHTXBA,
            NULLIF(RTRIM(APVNTX), '') AS APVNTX,
            NULLIF(RTRIM(APPAYT), '') AS APPAYT
        FROM StgDeduplicado
        WHERE rn = 1
    ),
    StgConHash AS (
        SELECT
            n.*,
            HASHBYTES('SHA2_256', (SELECT n.* FOR XML RAW, BINARY BASE64)) AS HashDiff
        FROM StgNormalizado n
    )
    MERGE [int].factCompras AS destino
        USING StgConHash AS origen
        ON destino.PLCMPY = origen.PLCMPY AND destino.PLDCPX = origen.PLDCPX AND destino.PLDCYR = origen.PLDCYR AND destino.PLDCSQ = origen.PLDCSQ AND destino.PLLINE = origen.PLLINE
    WHEN MATCHED AND destino.HashDiff <> origen.HashDiff THEN
        UPDATE SET
            PLCMPY = origen.PLCMPY,
            PLDCPX = origen.PLDCPX,
            PLDCYR = origen.PLDCYR,
            PLDCSQ = origen.PLDCSQ,
            PLLINE = origen.PLLINE,
            PLVNDR = origen.PLVNDR,
            PLINV = origen.PLINV,
            PLTYPE = origen.PLTYPE,
            PLGLDT = origen.PLGLDT,
            PLAMT = origen.PLAMT,
            PLBAMT = origen.PLBAMT,
            PLDESC = origen.PLDESC,
            PLUSER = origen.PLUSER,
            PLEDTE = origen.PLEDTE,
            PLETIM = origen.PLETIM,
            PLRESN = origen.PLRESN,
            APHPND = origen.APHPND,
            APHBNK = origen.APHBNK,
            APHCUR = origen.APHCUR,
            APHOLD = origen.APHOLD,
            AINVDT = origen.AINVDT,
            ADUEDT = origen.ADUEDT,
            ADISCD = origen.ADISCD,
            APCINA = origen.APCINA,
            APCAMP = origen.APCAMP,
            APCOUT = origen.APCOUT,
            APPORD = origen.APPORD,
            APTERM = origen.APTERM,
            APSTAT = origen.APSTAT,
            APPAYS = origen.APPAYS,
            PHHTRT = origen.PHHTRT,
            PHTXBA = origen.PHTXBA,
            APVNTX = origen.APVNTX,
            APPAYT = origen.APPAYT,
            HashDiff      = origen.HashDiff,
            FechaCargaInt = SYSDATETIME(),
            RunId         = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (PLCMPY, PLDCPX, PLDCYR, PLDCSQ, PLLINE, PLVNDR, PLINV, PLTYPE, PLGLDT, PLAMT, PLBAMT, PLDESC, PLUSER, PLEDTE, PLETIM, PLRESN, APHPND, APHBNK, APHCUR, APHOLD, AINVDT, ADUEDT, ADISCD, APCINA, APCAMP, APCOUT, APPORD, APTERM, APSTAT, APPAYS, PHHTRT, PHTXBA, APVNTX, APPAYT, HashDiff, RunId)
        VALUES (origen.PLCMPY, origen.PLDCPX, origen.PLDCYR, origen.PLDCSQ, origen.PLLINE, origen.PLVNDR, origen.PLINV, origen.PLTYPE, origen.PLGLDT, origen.PLAMT, origen.PLBAMT, origen.PLDESC, origen.PLUSER, origen.PLEDTE, origen.PLETIM, origen.PLRESN, origen.APHPND, origen.APHBNK, origen.APHCUR, origen.APHOLD, origen.AINVDT, origen.ADUEDT, origen.ADISCD, origen.APCINA, origen.APCAMP, origen.APCOUT, origen.APPORD, origen.APTERM, origen.APSTAT, origen.APPAYS, origen.PHHTRT, origen.PHTXBA, origen.APVNTX, origen.APPAYT, origen.HashDiff, @RunId)
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

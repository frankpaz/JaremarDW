-- 109: merge Bronze -> Silver para dimCliente.

CREATE OR ALTER PROCEDURE [int].usp_MergeDimCliente
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.dimCliente);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH StgDeduplicado AS (
        SELECT s.*,
               ROW_NUMBER() OVER (PARTITION BY s.CCUST ORDER BY s.CMENDT DESC, s.CMENTM DESC) AS rn
        FROM stg.dimCliente s
        WHERE s.CCUST IS NOT NULL
    ),
    StgNormalizado AS (
        SELECT
            s.CCUST                                                        AS CCUST,
            NULLIF(RTRIM(s.CNME), '')                                      AS CNME,
            NULLIF(RTRIM(s.CMALPH), '')                                    AS CMALPH,
            NULLIF(RTRIM(s.CAD1), '')                                      AS CAD1,
            NULLIF(RTRIM(s.CAD2), '')                                      AS CAD2,
            NULLIF(RTRIM(s.CAD3), '')                                      AS CAD3,
            NULLIF(RTRIM(s.CSTE), '')                                      AS CSTE,
            NULLIF(RTRIM(s.CZIP), '')                                      AS CZIP,
            NULLIF(RTRIM(s.CCOUN), '')                                     AS CCOUN,
            NULLIF(RTRIM(s.CTYPE), '')                                     AS CTYPE,
            s.CCOMP                                                        AS CCOMP,
            s.CCCUS                                                        AS CCCUS,
            NULLIF(RTRIM(s.CREG), '')                                      AS CREG,
            NULLIF(RTRIM(s.CMPREG), '')                                    AS CMPREG,
            NULLIF(RTRIM(s.CDEA1), '')                                     AS CDEA1,
            s.CSAL                                                         AS CSAL,
            NULLIF(RTRIM(s.CTERM), '')                                     AS CTERM,
            NULLIF(RTRIM(s.CTAX), '')                                      AS CTAX,
            NULLIF(RTRIM(s.CTXID), '')                                     AS CTXID,
            NULLIF(RTRIM(s.CPCD), '')                                      AS CPCD,
            NULLIF(RTRIM(s.CCURR), '')                                     AS CCURR,
            NULLIF(RTRIM(s.CWHSE), '')                                     AS CWHSE,
            NULLIF(RTRIM(s.CROUT), '')                                     AS CROUT,
            NULLIF(RTRIM(s.CMDFOT), '')                                    AS CMDFOT,
            NULLIF(RTRIM(s.CCON), '')                                      AS CCON,
            NULLIF(RTRIM(s.CPHON), '')                                     AS CPHON,
            s.CRDOL                                                        AS CRDOL,
            s.CDLIM                                                        AS CDLIM,
            s.CAPD                                                         AS CAPD,
            s.CAIS                                                         AS CAIS,
            TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(s.CLAST AS BIGINT)))   AS CLAST,
            TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(s.CLPDT AS BIGINT)))   AS CLPDT,
            s.CLPAM                                                        AS CLPAM,
            NULLIF(RTRIM(s.CMHOLD), '')                                    AS CMHOLD,
            TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(s.CMDCRT AS BIGINT)))  AS CMDCRT,
            TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(s.CMENDT AS BIGINT)))  AS CMENDT,
            TRY_CONVERT(TIME(0), STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(6), CAST(s.CMENTM AS BIGINT)), 6), 3, 0, ':'), 6, 0, ':')) AS CMENTM,
            NULLIF(RTRIM(s.CMENUS), '')                                    AS CMENUS,
            TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(s.CLDTE AS BIGINT)))   AS CLDTE,
            TRY_CONVERT(TIME(0), STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(6), CAST(s.CLTME AS BIGINT)), 6), 3, 0, ':'), 6, 0, ':')) AS CLTME,
            NULLIF(RTRIM(s.CLUSR), '')                                     AS CLUSR
        FROM StgDeduplicado s
        WHERE s.rn = 1
    ),
    StgConHash AS (
        SELECT
            n.*,
            HASHBYTES('SHA2_256', (SELECT n.* FOR XML RAW, BINARY BASE64)) AS HashDiff
        FROM StgNormalizado n
    )
    MERGE [int].dimCliente AS destino
        USING StgConHash AS origen
        ON destino.CCUST = origen.CCUST
    WHEN MATCHED AND destino.HashDiff <> origen.HashDiff THEN
        UPDATE SET
            CNME          = origen.CNME,
            CMALPH        = origen.CMALPH,
            CAD1          = origen.CAD1,
            CAD2          = origen.CAD2,
            CAD3          = origen.CAD3,
            CSTE          = origen.CSTE,
            CZIP          = origen.CZIP,
            CCOUN         = origen.CCOUN,
            CTYPE         = origen.CTYPE,
            CCOMP         = origen.CCOMP,
            CCCUS         = origen.CCCUS,
            CREG          = origen.CREG,
            CMPREG        = origen.CMPREG,
            CDEA1         = origen.CDEA1,
            CSAL          = origen.CSAL,
            CTERM         = origen.CTERM,
            CTAX          = origen.CTAX,
            CTXID         = origen.CTXID,
            CPCD          = origen.CPCD,
            CCURR         = origen.CCURR,
            CWHSE         = origen.CWHSE,
            CROUT         = origen.CROUT,
            CMDFOT        = origen.CMDFOT,
            CCON          = origen.CCON,
            CPHON         = origen.CPHON,
            CRDOL         = origen.CRDOL,
            CDLIM         = origen.CDLIM,
            CAPD          = origen.CAPD,
            CAIS          = origen.CAIS,
            CLAST         = origen.CLAST,
            CLPDT         = origen.CLPDT,
            CLPAM         = origen.CLPAM,
            CMHOLD        = origen.CMHOLD,
            CMDCRT        = origen.CMDCRT,
            CMENDT        = origen.CMENDT,
            CMENTM        = origen.CMENTM,
            CMENUS        = origen.CMENUS,
            CLDTE         = origen.CLDTE,
            CLTME         = origen.CLTME,
            CLUSR         = origen.CLUSR,
            EsVigente     = 1,
            HashDiff      = origen.HashDiff,
            FechaCargaInt = SYSDATETIME(),
            RunId         = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (
            CCUST, CNME, CMALPH, CAD1, CAD2, CAD3, CSTE, CZIP, CCOUN, CTYPE,
            CCOMP, CCCUS, CREG, CMPREG, CDEA1, CSAL, CTERM, CTAX, CTXID, CPCD,
            CCURR, CWHSE, CROUT, CMDFOT, CCON, CPHON, CRDOL, CDLIM, CAPD, CAIS,
            CLAST, CLPDT, CLPAM, CMHOLD, CMDCRT, CMENDT, CMENTM, CMENUS,
            CLDTE, CLTME, CLUSR, HashDiff, RunId
        )
        VALUES (
            origen.CCUST, origen.CNME, origen.CMALPH, origen.CAD1, origen.CAD2, origen.CAD3, origen.CSTE, origen.CZIP, origen.CCOUN, origen.CTYPE,
            origen.CCOMP, origen.CCCUS, origen.CREG, origen.CMPREG, origen.CDEA1, origen.CSAL, origen.CTERM, origen.CTAX, origen.CTXID, origen.CPCD,
            origen.CCURR, origen.CWHSE, origen.CROUT, origen.CMDFOT, origen.CCON, origen.CPHON, origen.CRDOL, origen.CDLIM, origen.CAPD, origen.CAIS,
            origen.CLAST, origen.CLPDT, origen.CLPAM, origen.CMHOLD, origen.CMDCRT, origen.CMENDT, origen.CMENTM, origen.CMENUS,
            origen.CLDTE, origen.CLTME, origen.CLUSR, origen.HashDiff, @RunId
        )
    WHEN NOT MATCHED BY SOURCE AND destino.EsVigente = 1 THEN
        UPDATE SET EsVigente = 0, FechaCargaInt = SYSDATETIME(), RunId = @RunId
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

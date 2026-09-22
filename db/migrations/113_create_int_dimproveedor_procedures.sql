-- 113: merge Bronze -> Silver para dimProveedor.

CREATE OR ALTER PROCEDURE [int].usp_MergeDimProveedor
    @RunId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.dimProveedor);

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL);

    ;WITH StgDeduplicado AS (
        SELECT s.*,
               ROW_NUMBER() OVER (PARTITION BY s.VENDOR ORDER BY (SELECT NULL)) AS rn
        FROM stg.dimProveedor s
        WHERE s.VENDOR IS NOT NULL
    ),
    StgNormalizado AS (
        SELECT
            s.VENDOR                                                       AS VENDOR,
            NULLIF(RTRIM(s.VNDNAM), '')                                    AS VNDNAM,
            NULLIF(RTRIM(s.VNALPH), '')                                    AS VNALPH,
            NULLIF(RTRIM(s.VNDAD1), '')                                    AS VNDAD1,
            NULLIF(RTRIM(s.VNDAD2), '')                                    AS VNDAD2,
            NULLIF(RTRIM(s.VSTATE), '')                                    AS VSTATE,
            NULLIF(RTRIM(s.VCOUN), '')                                     AS VCOUN,
            NULLIF(RTRIM(s.VTYPE), '')                                     AS VTYPE,
            s.VCMPNY                                                       AS VCMPNY,
            NULLIF(RTRIM(s.VTERMS), '')                                    AS VTERMS,
            s.VPAYTO                                                       AS VPAYTO,
            NULLIF(RTRIM(s.VCURR), '')                                     AS VCURR,
            NULLIF(RTRIM(s.VPAYTY), '')                                    AS VPAYTY,
            NULLIF(RTRIM(s.V1TIME), '')                                    AS V1TIME,
            NULLIF(RTRIM(s.VCON), '')                                      AS VCON,
            NULLIF(RTRIM(s.VPHONE), '')                                    AS VPHONE,
            NULLIF(RTRIM(s.VTAX), '')                                      AS VTAX,
            NULLIF(RTRIM(s.VTAXCD), '')                                    AS VTAXCD,
            NULLIF(RTRIM(s.VMIDNM), '')                                    AS VMIDNM,
            NULLIF(RTRIM(s.V1099), '')                                     AS V1099,
            NULLIF(RTRIM(s.V1099C), '')                                    AS V1099C,
            TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(s.VDTLPD AS BIGINT)))  AS VDTLPD,
            s.VPYTYR                                                       AS VPYTYR,
            s.VDPURS                                                       AS VDPURS,
            NULLIF(RTRIM(s.VHOLD), '')                                     AS VHOLD,
            NULLIF(RTRIM(s.VNSTAT), '')                                    AS VNSTAT,
            NULLIF(RTRIM(s.VMBANK), '')                                    AS VMBANK,
            NULLIF(RTRIM(s.VMBNKC), '')                                    AS VMBNKC,
            NULLIF(RTRIM(s.VMBRNO), '')                                    AS VMBRNO,
            NULLIF(RTRIM(s.VMBNKA), '')                                    AS VMBNKA,
            NULLIF(RTRIM(s.VMCARR), '')                                    AS VMCARR,
            NULLIF(RTRIM(s.VMMNTR), '')                                    AS VMMNTR,
            NULLIF(RTRIM(s.VMLANG), '')                                    AS VMLANG
        FROM StgDeduplicado s
        WHERE s.rn = 1
    ),
    StgConHash AS (
        SELECT
            n.*,
            HASHBYTES('SHA2_256', (SELECT n.* FOR XML RAW, BINARY BASE64)) AS HashDiff
        FROM StgNormalizado n
    )
    MERGE [int].dimProveedor AS destino
        USING StgConHash AS origen
        ON destino.VENDOR = origen.VENDOR
    WHEN MATCHED AND destino.HashDiff <> origen.HashDiff THEN
        UPDATE SET
            VNDNAM        = origen.VNDNAM,
            VNALPH        = origen.VNALPH,
            VNDAD1        = origen.VNDAD1,
            VNDAD2        = origen.VNDAD2,
            VSTATE        = origen.VSTATE,
            VCOUN         = origen.VCOUN,
            VTYPE         = origen.VTYPE,
            VCMPNY        = origen.VCMPNY,
            VTERMS        = origen.VTERMS,
            VPAYTO        = origen.VPAYTO,
            VCURR         = origen.VCURR,
            VPAYTY        = origen.VPAYTY,
            V1TIME        = origen.V1TIME,
            VCON          = origen.VCON,
            VPHONE        = origen.VPHONE,
            VTAX          = origen.VTAX,
            VTAXCD        = origen.VTAXCD,
            VMIDNM        = origen.VMIDNM,
            V1099         = origen.V1099,
            V1099C        = origen.V1099C,
            VDTLPD        = origen.VDTLPD,
            VPYTYR        = origen.VPYTYR,
            VDPURS        = origen.VDPURS,
            VHOLD         = origen.VHOLD,
            VNSTAT        = origen.VNSTAT,
            VMBANK        = origen.VMBANK,
            VMBNKC        = origen.VMBNKC,
            VMBRNO        = origen.VMBRNO,
            VMBNKA        = origen.VMBNKA,
            VMCARR        = origen.VMCARR,
            VMMNTR        = origen.VMMNTR,
            VMLANG        = origen.VMLANG,
            EsVigente     = 1,
            HashDiff      = origen.HashDiff,
            FechaCargaInt = SYSDATETIME(),
            RunId         = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (
            VENDOR, VNDNAM, VNALPH, VNDAD1, VNDAD2, VSTATE, VCOUN, VTYPE, VCMPNY,
            VTERMS, VPAYTO, VCURR, VPAYTY, V1TIME, VCON, VPHONE, VTAX, VTAXCD, VMIDNM,
            V1099, V1099C, VDTLPD, VPYTYR, VDPURS, VHOLD, VNSTAT,
            VMBANK, VMBNKC, VMBRNO, VMBNKA, VMCARR, VMMNTR, VMLANG,
            HashDiff, RunId
        )
        VALUES (
            origen.VENDOR, origen.VNDNAM, origen.VNALPH, origen.VNDAD1, origen.VNDAD2, origen.VSTATE, origen.VCOUN, origen.VTYPE, origen.VCMPNY,
            origen.VTERMS, origen.VPAYTO, origen.VCURR, origen.VPAYTY, origen.V1TIME, origen.VCON, origen.VPHONE, origen.VTAX, origen.VTAXCD, origen.VMIDNM,
            origen.V1099, origen.V1099C, origen.VDTLPD, origen.VPYTYR, origen.VDPURS, origen.VHOLD, origen.VNSTAT,
            origen.VMBANK, origen.VMBNKC, origen.VMBRNO, origen.VMBNKA, origen.VMCARR, origen.VMMNTR, origen.VMLANG,
            origen.HashDiff, @RunId
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

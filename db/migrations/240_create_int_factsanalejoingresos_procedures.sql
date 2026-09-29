-- 240: Bronze -> Silver para factSanAlejoIngresos (dominio SanAlejo). MERGE incremental por la llave CODCIA +
-- NUMDOC con HashDiff sobre todas las columnas (mismo esquema que factBasculaBufalo, migracion 204):
--   llave nueva             -> INSERT (FechaAlta)
--   llave con hash distinto -> UPDATE (FechaUltimoCambio, RunId)
--   hash igual              -> se ignora
--   llave que falta         -> EsVigente = 0 (nunca se borra), solo si su FECDOC cae dentro de la ventana
--                              que el extract trajo completa (@VentanaDesde; NULL = todo desde 2025).
--                              Si reaparece, vuelve a EsVigente = 1.
-- Resguardo: si la corrida daria de baja mas de @MaxBajas documentos aborta sin tocar nada.
-- Compatible con SQL Server 2016.

CREATE OR ALTER PROCEDURE [int].usp_MergeFactSanAlejoIngresos
    @RunId         INT,
    @VentanaDesde  DATE = NULL,
    @MaxBajas      INT  = 200
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.factSanAlejoIngresos);
    IF @FilasLeidas = 0
        THROW 50001, 'stg.factSanAlejoIngresos esta vacio: no se procesa (revisar el extract).', 1;

    CREATE TABLE #Normalizado (
        [CODCIA] INT NOT NULL,
        [CODSUC] INT NULL,
        [NUMDOC] BIGINT NOT NULL,
        [FECDOC] DATE NULL,
        [HORDOC] TIME(0) NULL,
        [PLACA] NVARCHAR(9) NULL,
        [NOMBRE] NVARCHAR(30) NULL,
        [CODCLI] INT NULL,
        [CONDUC] NVARCHAR(30) NULL,
        [TIPOP] NVARCHAR(5) NULL,
        [COMEN1] NVARCHAR(50) NULL,
        [COMEN2] NVARCHAR(50) NULL,
        [COMEN3] NVARCHAR(50) NULL,
        [BRUTO] DECIMAL(7,0) NULL,
        [TARA] DECIMAL(7,0) NULL,
        [NETO] DECIMAL(7,0) NULL,
        [CODTRA] INT NULL,
        [CODLOC] INT NULL,
        [SELLO1] NVARCHAR(10) NULL,
        [SELLO2] NVARCHAR(10) NULL,
        [SELLO3] NVARCHAR(10) NULL,
        [SELLO4] NVARCHAR(10) NULL,
        [SELLO5] NVARCHAR(10) NULL,
        [SELLO6] NVARCHAR(10) NULL,
        [SELLO7] NVARCHAR(10) NULL,
        [SELLO8] NVARCHAR(10) NULL,
        [SELLO9] NVARCHAR(10) NULL,
        [USUARI] NVARCHAR(10) NULL,
        [PORACI] DECIMAL(5,3) NULL,
        [PORHUM] DECIMAL(5,3) NULL,
        [REFDOC] BIGINT NULL,
        [REFPES] DECIMAL(7,0) NULL,
        [FECENV] DATE NULL,
        [MARMOD] NVARCHAR(1) NULL,
        [USUMOD] NVARCHAR(10) NULL,
        [FECMOD] DATE NULL,
        [NUMTIK] NVARCHAR(10) NULL,
        [FECSAL] DATE NULL,
        [HORSAL] TIME(0) NULL,
        [CERTIF] NVARCHAR(2) NULL,
        [MODEL] NVARCHAR(5) NULL,
        [PROSUS] NVARCHAR(2) NULL,
        [BOLVEN] DECIMAL(20,0) NULL,
        [NOPEDI] BIGINT NULL,
        [FEPEDI] DATE NULL,
        [NUMFAC] BIGINT NULL,
        [SEMAN] INT NULL,
        [PEROPR] INT NULL,
        [MESC] INT NULL,
        [AÑOC] INT NULL,
        [P1NPLA] NVARCHAR(10) NULL,
        [P2NPLAC] NVARCHAR(10) NULL,
        [M1IDM] NVARCHAR(20) NULL,
        [T1CTRA] NVARCHAR(10) NULL,
        [CARAC1] NVARCHAR(20) NULL,
        [CARAC3] NVARCHAR(20) NULL,
        [CARAC5] NVARCHAR(20) NULL,
        [DIGIT1] DECIMAL(15,2) NULL,
        [DIGIT2] DECIMAL(15,2) NULL,
        [DIGIT6] DECIMAL(15,0) NULL,
        [DIGIT7] DECIMAL(15,0) NULL,
        [HORAB] TIME(0) NULL,
        [HORAT] TIME(0) NULL,
        [FECHAT] DATE NULL,
        [FECHAB] DATE NULL,
        [IDING] BIGINT NULL,
        [IDSAL] BIGINT NULL,
        [CONRAC] NVARCHAR(1) NULL,
        [CONCAL] NVARCHAR(1) NULL
    );

    INSERT INTO #Normalizado ([CODCIA], [CODSUC], [NUMDOC], [FECDOC], [HORDOC], [PLACA], [NOMBRE], [CODCLI], [CONDUC], [TIPOP], [COMEN1], [COMEN2], [COMEN3], [BRUTO], [TARA], [NETO], [CODTRA], [CODLOC], [SELLO1], [SELLO2], [SELLO3], [SELLO4], [SELLO5], [SELLO6], [SELLO7], [SELLO8], [SELLO9], [USUARI], [PORACI], [PORHUM], [REFDOC], [REFPES], [FECENV], [MARMOD], [USUMOD], [FECMOD], [NUMTIK], [FECSAL], [HORSAL], [CERTIF], [MODEL], [PROSUS], [BOLVEN], [NOPEDI], [FEPEDI], [NUMFAC], [SEMAN], [PEROPR], [MESC], [AÑOC], [P1NPLA], [P2NPLAC], [M1IDM], [T1CTRA], [CARAC1], [CARAC3], [CARAC5], [DIGIT1], [DIGIT2], [DIGIT6], [DIGIT7], [HORAB], [HORAT], [FECHAT], [FECHAB], [IDING], [IDSAL], [CONRAC], [CONCAL])
    SELECT
        CAST(s.[CODCIA] AS INT),
        CAST(NULLIF(s.[CODSUC], 0) AS INT),
        CAST(s.[NUMDOC] AS BIGINT),
        TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(NULLIF(s.[FECDOC], 0) AS BIGINT))),
        CASE WHEN s.[HORDOC] IS NULL OR s.[HORDOC] = 0 THEN NULL ELSE TRY_CONVERT(TIME(0), STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(8), CAST(s.[HORDOC] AS BIGINT)), 6), 3, 0, ':'), 6, 0, ':')) END,
        NULLIF(LTRIM(RTRIM(s.[PLACA])), ''),
        NULLIF(LTRIM(RTRIM(s.[NOMBRE])), ''),
        CAST(NULLIF(s.[CODCLI], 0) AS INT),
        NULLIF(LTRIM(RTRIM(s.[CONDUC])), ''),
        NULLIF(LTRIM(RTRIM(s.[TIPOP])), ''),
        NULLIF(LTRIM(RTRIM(s.[COMEN1])), ''),
        NULLIF(LTRIM(RTRIM(s.[COMEN2])), ''),
        NULLIF(LTRIM(RTRIM(s.[COMEN3])), ''),
        CAST(s.[BRUTO] AS DECIMAL(7,0)),
        CAST(s.[TARA] AS DECIMAL(7,0)),
        CAST(s.[NETO] AS DECIMAL(7,0)),
        CAST(NULLIF(s.[CODTRA], 0) AS INT),
        CAST(NULLIF(s.[CODLOC], 0) AS INT),
        NULLIF(LTRIM(RTRIM(s.[SELLO1])), ''),
        NULLIF(LTRIM(RTRIM(s.[SELLO2])), ''),
        NULLIF(LTRIM(RTRIM(s.[SELLO3])), ''),
        NULLIF(LTRIM(RTRIM(s.[SELLO4])), ''),
        NULLIF(LTRIM(RTRIM(s.[SELLO5])), ''),
        NULLIF(LTRIM(RTRIM(s.[SELLO6])), ''),
        NULLIF(LTRIM(RTRIM(s.[SELLO7])), ''),
        NULLIF(LTRIM(RTRIM(s.[SELLO8])), ''),
        NULLIF(LTRIM(RTRIM(s.[SELLO9])), ''),
        NULLIF(LTRIM(RTRIM(s.[USUARI])), ''),
        CAST(s.[PORACI] AS DECIMAL(5,3)),
        CAST(s.[PORHUM] AS DECIMAL(5,3)),
        CAST(NULLIF(s.[REFDOC], 0) AS BIGINT),
        CAST(s.[REFPES] AS DECIMAL(7,0)),
        TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(NULLIF(s.[FECENV], 0) AS BIGINT))),
        NULLIF(LTRIM(RTRIM(s.[MARMOD])), ''),
        NULLIF(LTRIM(RTRIM(s.[USUMOD])), ''),
        TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(NULLIF(s.[FECMOD], 0) AS BIGINT))),
        NULLIF(LTRIM(RTRIM(s.[NUMTIK])), ''),
        TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(NULLIF(s.[FECSAL], 0) AS BIGINT))),
        CASE WHEN s.[HORSAL] IS NULL OR s.[HORSAL] = 0 THEN NULL ELSE TRY_CONVERT(TIME(0), STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(8), CAST(s.[HORSAL] AS BIGINT)), 6), 3, 0, ':'), 6, 0, ':')) END,
        NULLIF(LTRIM(RTRIM(s.[CERTIF])), ''),
        NULLIF(LTRIM(RTRIM(s.[MODEL])), ''),
        NULLIF(LTRIM(RTRIM(s.[PROSUS])), ''),
        CAST(NULLIF(s.[BOLVEN], 0) AS DECIMAL(20,0)),
        CAST(NULLIF(s.[NOPEDI], 0) AS BIGINT),
        TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(NULLIF(s.[FEPEDI], 0) AS BIGINT))),
        CAST(NULLIF(s.[NUMFAC], 0) AS BIGINT),
        CAST(NULLIF(s.[SEMAN], 0) AS INT),
        CAST(NULLIF(s.[PEROPR], 0) AS INT),
        CAST(NULLIF(s.[MESC], 0) AS INT),
        CAST(NULLIF(s.[AÑOC], 0) AS INT),
        NULLIF(LTRIM(RTRIM(s.[P1NPLA])), ''),
        NULLIF(LTRIM(RTRIM(s.[P2NPLAC])), ''),
        NULLIF(LTRIM(RTRIM(s.[M1IDM])), ''),
        NULLIF(LTRIM(RTRIM(s.[T1CTRA])), ''),
        NULLIF(LTRIM(RTRIM(s.[CARAC1])), ''),
        NULLIF(LTRIM(RTRIM(s.[CARAC3])), ''),
        NULLIF(LTRIM(RTRIM(s.[CARAC5])), ''),
        CAST(s.[DIGIT1] AS DECIMAL(15,2)),
        CAST(s.[DIGIT2] AS DECIMAL(15,2)),
        CAST(s.[DIGIT6] AS DECIMAL(15,0)),
        CAST(s.[DIGIT7] AS DECIMAL(15,0)),
        CASE WHEN s.[HORAB] IS NULL OR s.[HORAB] = 0 THEN NULL ELSE TRY_CONVERT(TIME(0), STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(8), CAST(s.[HORAB] AS BIGINT)), 6), 3, 0, ':'), 6, 0, ':')) END,
        CASE WHEN s.[HORAT] IS NULL OR s.[HORAT] = 0 THEN NULL ELSE TRY_CONVERT(TIME(0), STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(8), CAST(s.[HORAT] AS BIGINT)), 6), 3, 0, ':'), 6, 0, ':')) END,
        TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(NULLIF(s.[FECHAT], 0) AS BIGINT))),
        TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(NULLIF(s.[FECHAB], 0) AS BIGINT))),
        CAST(NULLIF(s.[IDING], 0) AS BIGINT),
        CAST(NULLIF(s.[IDSAL], 0) AS BIGINT),
        NULLIF(LTRIM(RTRIM(s.[CONRAC])), ''),
        NULLIF(LTRIM(RTRIM(s.[CONCAL])), '')
    FROM stg.factSanAlejoIngresos s
    WHERE s.[CODCIA] IS NOT NULL AND s.[NUMDOC] IS NOT NULL;

    ;WITH Numerado AS (
        SELECT n.*,
               COUNT(*) OVER (PARTITION BY CODCIA, NUMDOC) AS Repeticiones,
               ROW_NUMBER() OVER (PARTITION BY CODCIA, NUMDOC ORDER BY FECMOD DESC, HORDOC DESC) AS rn
        FROM #Normalizado n
    ),
    Unico AS (
        SELECT [CODCIA], [CODSUC], [NUMDOC], [FECDOC], [HORDOC], [PLACA], [NOMBRE], [CODCLI], [CONDUC], [TIPOP], [COMEN1], [COMEN2], [COMEN3], [BRUTO], [TARA], [NETO], [CODTRA], [CODLOC], [SELLO1], [SELLO2], [SELLO3], [SELLO4], [SELLO5], [SELLO6], [SELLO7], [SELLO8], [SELLO9], [USUARI], [PORACI], [PORHUM], [REFDOC], [REFPES], [FECENV], [MARMOD], [USUMOD], [FECMOD], [NUMTIK], [FECSAL], [HORSAL], [CERTIF], [MODEL], [PROSUS], [BOLVEN], [NOPEDI], [FEPEDI], [NUMFAC], [SEMAN], [PEROPR], [MESC], [AÑOC], [P1NPLA], [P2NPLAC], [M1IDM], [T1CTRA], [CARAC1], [CARAC3], [CARAC5], [DIGIT1], [DIGIT2], [DIGIT6], [DIGIT7], [HORAB], [HORAT], [FECHAT], [FECHAB], [IDING], [IDSAL], [CONRAC], [CONCAL], Repeticiones FROM Numerado WHERE rn = 1
    )
    SELECT u.*, HASHBYTES('SHA2_256', (SELECT u.* FOR XML RAW, BINARY BASE64)) AS HashDiff
    INTO #Origen
    FROM Unico u;

    CREATE UNIQUE CLUSTERED INDEX IX_Origen ON #Origen (CODCIA, NUMDOC);
    DECLARE @Llaves INT = (SELECT COUNT(*) FROM #Origen);

    DECLARE @Bajas INT = (
        SELECT COUNT(*) FROM [int].factSanAlejoIngresos d
        WHERE d.EsVigente = 1
          AND (@VentanaDesde IS NULL OR d.FECDOC >= @VentanaDesde)
          AND NOT EXISTS (SELECT 1 FROM #Origen o WHERE o.CODCIA = d.CODCIA AND o.NUMDOC = d.NUMDOC)
    );
    IF @Bajas > @MaxBajas
    BEGIN
        DECLARE @Msg NVARCHAR(400) = CONCAT(N'La corrida daria de baja ', @Bajas, N' documentos (limite ', @MaxBajas,
            N'): se aborta sin cambios. Revisar el extract; si las bajas son reales, correr silver con --max-bajas.');
        THROW 50003, @Msg, 1;
    END

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL, EsVigente BIT NULL);

    MERGE [int].factSanAlejoIngresos AS destino
        USING #Origen AS origen
        ON destino.CODCIA = origen.CODCIA AND destino.NUMDOC = origen.NUMDOC
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente = 0) THEN
        UPDATE SET
            [CODSUC]    = origen.[CODSUC],
            [FECDOC]    = origen.[FECDOC],
            [HORDOC]    = origen.[HORDOC],
            [PLACA]     = origen.[PLACA],
            [NOMBRE]    = origen.[NOMBRE],
            [CODCLI]    = origen.[CODCLI],
            [CONDUC]    = origen.[CONDUC],
            [TIPOP]     = origen.[TIPOP],
            [COMEN1]    = origen.[COMEN1],
            [COMEN2]    = origen.[COMEN2],
            [COMEN3]    = origen.[COMEN3],
            [BRUTO]     = origen.[BRUTO],
            [TARA]      = origen.[TARA],
            [NETO]      = origen.[NETO],
            [CODTRA]    = origen.[CODTRA],
            [CODLOC]    = origen.[CODLOC],
            [SELLO1]    = origen.[SELLO1],
            [SELLO2]    = origen.[SELLO2],
            [SELLO3]    = origen.[SELLO3],
            [SELLO4]    = origen.[SELLO4],
            [SELLO5]    = origen.[SELLO5],
            [SELLO6]    = origen.[SELLO6],
            [SELLO7]    = origen.[SELLO7],
            [SELLO8]    = origen.[SELLO8],
            [SELLO9]    = origen.[SELLO9],
            [USUARI]    = origen.[USUARI],
            [PORACI]    = origen.[PORACI],
            [PORHUM]    = origen.[PORHUM],
            [REFDOC]    = origen.[REFDOC],
            [REFPES]    = origen.[REFPES],
            [FECENV]    = origen.[FECENV],
            [MARMOD]    = origen.[MARMOD],
            [USUMOD]    = origen.[USUMOD],
            [FECMOD]    = origen.[FECMOD],
            [NUMTIK]    = origen.[NUMTIK],
            [FECSAL]    = origen.[FECSAL],
            [HORSAL]    = origen.[HORSAL],
            [CERTIF]    = origen.[CERTIF],
            [MODEL]     = origen.[MODEL],
            [PROSUS]    = origen.[PROSUS],
            [BOLVEN]    = origen.[BOLVEN],
            [NOPEDI]    = origen.[NOPEDI],
            [FEPEDI]    = origen.[FEPEDI],
            [NUMFAC]    = origen.[NUMFAC],
            [SEMAN]     = origen.[SEMAN],
            [PEROPR]    = origen.[PEROPR],
            [MESC]      = origen.[MESC],
            [AÑOC]      = origen.[AÑOC],
            [P1NPLA]    = origen.[P1NPLA],
            [P2NPLAC]   = origen.[P2NPLAC],
            [M1IDM]     = origen.[M1IDM],
            [T1CTRA]    = origen.[T1CTRA],
            [CARAC1]    = origen.[CARAC1],
            [CARAC3]    = origen.[CARAC3],
            [CARAC5]    = origen.[CARAC5],
            [DIGIT1]    = origen.[DIGIT1],
            [DIGIT2]    = origen.[DIGIT2],
            [DIGIT6]    = origen.[DIGIT6],
            [DIGIT7]    = origen.[DIGIT7],
            [HORAB]     = origen.[HORAB],
            [HORAT]     = origen.[HORAT],
            [FECHAT]    = origen.[FECHAT],
            [FECHAB]    = origen.[FECHAB],
            [IDING]     = origen.[IDING],
            [IDSAL]     = origen.[IDSAL],
            [CONRAC]    = origen.[CONRAC],
            [CONCAL]    = origen.[CONCAL],
            Repeticiones = origen.Repeticiones,
            EsVigente   = 1,
            HashDiff    = origen.HashDiff,
            FechaUltimoCambio = SYSDATETIME(),
            FechaCargaInt = SYSDATETIME(),
            RunId       = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT ([CODCIA], [CODSUC], [NUMDOC], [FECDOC], [HORDOC], [PLACA], [NOMBRE], [CODCLI], [CONDUC], [TIPOP], [COMEN1], [COMEN2], [COMEN3], [BRUTO], [TARA], [NETO], [CODTRA], [CODLOC], [SELLO1], [SELLO2], [SELLO3], [SELLO4], [SELLO5], [SELLO6], [SELLO7], [SELLO8], [SELLO9], [USUARI], [PORACI], [PORHUM], [REFDOC], [REFPES], [FECENV], [MARMOD], [USUMOD], [FECMOD], [NUMTIK], [FECSAL], [HORSAL], [CERTIF], [MODEL], [PROSUS], [BOLVEN], [NOPEDI], [FEPEDI], [NUMFAC], [SEMAN], [PEROPR], [MESC], [AÑOC], [P1NPLA], [P2NPLAC], [M1IDM], [T1CTRA], [CARAC1], [CARAC3], [CARAC5], [DIGIT1], [DIGIT2], [DIGIT6], [DIGIT7], [HORAB], [HORAT], [FECHAT], [FECHAB], [IDING], [IDSAL], [CONRAC], [CONCAL], Repeticiones, HashDiff, RunId)
        VALUES (origen.[CODCIA], origen.[CODSUC], origen.[NUMDOC], origen.[FECDOC], origen.[HORDOC], origen.[PLACA], origen.[NOMBRE], origen.[CODCLI], origen.[CONDUC], origen.[TIPOP], origen.[COMEN1], origen.[COMEN2], origen.[COMEN3], origen.[BRUTO], origen.[TARA], origen.[NETO], origen.[CODTRA], origen.[CODLOC], origen.[SELLO1], origen.[SELLO2], origen.[SELLO3], origen.[SELLO4], origen.[SELLO5], origen.[SELLO6], origen.[SELLO7], origen.[SELLO8], origen.[SELLO9], origen.[USUARI], origen.[PORACI], origen.[PORHUM], origen.[REFDOC], origen.[REFPES], origen.[FECENV], origen.[MARMOD], origen.[USUMOD], origen.[FECMOD], origen.[NUMTIK], origen.[FECSAL], origen.[HORSAL], origen.[CERTIF], origen.[MODEL], origen.[PROSUS], origen.[BOLVEN], origen.[NOPEDI], origen.[FEPEDI], origen.[NUMFAC], origen.[SEMAN], origen.[PEROPR], origen.[MESC], origen.[AÑOC], origen.[P1NPLA], origen.[P2NPLAC], origen.[M1IDM], origen.[T1CTRA], origen.[CARAC1], origen.[CARAC3], origen.[CARAC5], origen.[DIGIT1], origen.[DIGIT2], origen.[DIGIT6], origen.[DIGIT7], origen.[HORAB], origen.[HORAT], origen.[FECHAT], origen.[FECHAB], origen.[IDING], origen.[IDSAL], origen.[CONRAC], origen.[CONCAL], origen.Repeticiones, origen.HashDiff, @RunId)
    WHEN NOT MATCHED BY SOURCE AND destino.EsVigente = 1
                              AND (@VentanaDesde IS NULL OR destino.FECDOC >= @VentanaDesde) THEN
        UPDATE SET EsVigente = 0, FechaUltimoCambio = SYSDATETIME(), FechaCargaInt = SYSDATETIME(), RunId = @RunId
    OUTPUT $action, inserted.EsVigente INTO #AccionesMerge;

    DECLARE @Ins INT = (SELECT COUNT(*) FROM #AccionesMerge WHERE Accion = 'INSERT');
    DECLARE @Act INT = (SELECT COUNT(*) FROM #AccionesMerge WHERE Accion = 'UPDATE' AND EsVigente = 1);
    DECLARE @Baj INT = (SELECT COUNT(*) FROM #AccionesMerge WHERE Accion = 'UPDATE' AND EsVigente = 0);

    SELECT
        @FilasLeidas                   AS FilasLeidas,
        @Ins                           AS FilasInsertadas,
        @Act                           AS FilasActualizadas,
        @Llaves - @Ins - @Act          AS FilasIgnoradas,
        @Baj                           AS FilasDadasDeBaja,
        @FilasLeidas - @Llaves         AS FilasRepetidas,
        0                              AS FilasSinFecha;

    DROP TABLE #Origen;
END
GO

-- 204: Bronze -> Silver para factBasculaBufalo. MERGE incremental por la llave construida
-- (BASCIA, NUMBOLET, FECHAGEN, HORAGEN; ver 203) con HashDiff sobre todas las columnas:
--   llave nueva            -> INSERT (FechaAlta)
--   llave con hash distinto -> UPDATE (FechaUltimoCambio, RunId)
--   hash igual             -> se ignora
--   llave que falta        -> EsVigente = 0 (nunca se borra), solo si su FECHAGEN cae dentro de la
--                             ventana que trajo el extract (@VentanaDesde; NULL = extract completo).
--                             Si reaparece, vuelve a EsVigente = 1.
-- Resguardo: si la corrida daria de baja mas de @MaxBajas boletas aborta sin tocar nada (un
-- extract incompleto no debe dar de baja datos buenos).
-- Filas repetidas en stg con la misma llave (identicas en el origen) se guardan una vez y
-- Repeticiones cuenta cuantas eran. Las filas sin FECHAGEN valida se ignoran.
-- Compatible con SQL Server 2016.

CREATE OR ALTER PROCEDURE [int].usp_MergeFactBasculaBufalo
    @RunId         INT,
    @VentanaDesde  DATE = NULL,
    @MaxBajas      INT  = 200
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.factBasculaBufalo);
    IF @FilasLeidas = 0
        THROW 50001, 'stg.factBasculaBufalo esta vacio: no se procesa (revisar el extract).', 1;

    CREATE TABLE #Normalizado (
        [BASCIA] INT NOT NULL,
        [NUMBOLET] INT NOT NULL,
        [FECHAGEN] DATE NULL,
        [HORAGEN] INT NOT NULL,
        [BASCUSER] INT NULL,
        [NUMENVIO] INT NULL,
        [BOLETY] INT NULL,
        [NUMPLACA] NVARCHAR(10) NULL,
        [MOTORITA] NVARCHAR(40) NULL,
        [ORIGEN] INT NULL,
        [NUMLUGAR] INT NULL,
        [PESOGEMAN] DECIMAL(15,0) NULL,
        [PESOTARA] DECIMAL(15,0) NULL,
        [FECHATAR] DATE NULL,
        [HORATARA] TIME(0) NULL,
        [PESOBRUT] DECIMAL(15,0) NULL,
        [FECHBRUT] DATE NULL,
        [HORABRUT] TIME(0) NULL,
        [PESONETO] DECIMAL(15,0) NULL,
        [DIFPESO] DECIMAL(15,0) NULL,
        [RIMPRESO] NVARCHAR(1) NULL,
        [ESTATUS] NVARCHAR(1) NULL,
        [NUMPROD] INT NULL,
        [NUMPROV] INT NULL,
        [MARCHAMO] NVARCHAR(60) NULL,
        [OBSERBA] NVARCHAR(60) NULL,
        [NUMDOCTS] NVARCHAR(60) NULL,
        [PESOAUDI] DECIMAL(15,0) NULL,
        [BASAUDIT] NVARCHAR(30) NULL,
        [MONTAR1] NVARCHAR(35) NULL,
        [MONTAR2] NVARCHAR(35) NULL,
        [MONTAR3] NVARCHAR(35) NULL,
        [MOMBRU1] NVARCHAR(35) NULL,
        [MOMBRU2] NVARCHAR(35) NULL,
        [MOMBRU3] NVARCHAR(35) NULL,
        [FECHATAR1] DATE NULL,
        [HORATARA1] TIME(0) NULL,
        [PESOTARA1] DECIMAL(15,0) NULL,
        [FECHATAR2] DATE NULL,
        [HORATARA2] TIME(0) NULL,
        [PESOTARA2] DECIMAL(15,0) NULL,
        [FECHATAR3] DATE NULL,
        [HORATARA3] TIME(0) NULL,
        [PESOTARA3] DECIMAL(15,0) NULL,
        [FECHBRUT1] DATE NULL,
        [HORABRUT1] TIME(0) NULL,
        [PESOBRUT1] DECIMAL(15,0) NULL,
        [FECHBRUT2] DATE NULL,
        [HORABRUT2] TIME(0) NULL,
        [PESOBRUT2] DECIMAL(15,0) NULL,
        [FECHBRUT3] DATE NULL,
        [HORABRUT3] TIME(0) NULL,
        [PESOBRUT3] DECIMAL(15,0) NULL,
        [PESOGEMAN1] DECIMAL(15,0) NULL,
        [PESOGEMAN2] DECIMAL(15,0) NULL,
        [PESOGEMAN3] DECIMAL(15,0) NULL,
        [PESONETO1] DECIMAL(15,0) NULL,
        [PESONETO2] DECIMAL(15,0) NULL,
        [PESONETO3] DECIMAL(15,0) NULL,
        [DIFPESO1] DECIMAL(15,0) NULL,
        [DIFPESO2] DECIMAL(15,0) NULL,
        [DIFPESO3] DECIMAL(15,0) NULL,
        [MARCACAM] NVARCHAR(30) NULL,
        [COLORCAM] NVARCHAR(30) NULL,
        [NUMDOCTO] NVARCHAR(10) NULL,
        [FECDCTOO] DATE NULL,
        [STATUS1] NVARCHAR(1) NULL,
        [STATUS2] NVARCHAR(1) NULL,
        [ENCARGADO] NVARCHAR(40) NULL,
        [ONLINE] NVARCHAR(30) NULL,
        [IDENTIN] NVARCHAR(15) NULL,
        [IDENTOUT] NVARCHAR(15) NULL
    );

    INSERT INTO #Normalizado ([BASCIA], [NUMBOLET], [FECHAGEN], [HORAGEN], [BASCUSER], [NUMENVIO], [BOLETY], [NUMPLACA], [MOTORITA], [ORIGEN], [NUMLUGAR], [PESOGEMAN], [PESOTARA], [FECHATAR], [HORATARA], [PESOBRUT], [FECHBRUT], [HORABRUT], [PESONETO], [DIFPESO], [RIMPRESO], [ESTATUS], [NUMPROD], [NUMPROV], [MARCHAMO], [OBSERBA], [NUMDOCTS], [PESOAUDI], [BASAUDIT], [MONTAR1], [MONTAR2], [MONTAR3], [MOMBRU1], [MOMBRU2], [MOMBRU3], [FECHATAR1], [HORATARA1], [PESOTARA1], [FECHATAR2], [HORATARA2], [PESOTARA2], [FECHATAR3], [HORATARA3], [PESOTARA3], [FECHBRUT1], [HORABRUT1], [PESOBRUT1], [FECHBRUT2], [HORABRUT2], [PESOBRUT2], [FECHBRUT3], [HORABRUT3], [PESOBRUT3], [PESOGEMAN1], [PESOGEMAN2], [PESOGEMAN3], [PESONETO1], [PESONETO2], [PESONETO3], [DIFPESO1], [DIFPESO2], [DIFPESO3], [MARCACAM], [COLORCAM], [NUMDOCTO], [FECDCTOO], [STATUS1], [STATUS2], [ENCARGADO], [ONLINE], [IDENTIN], [IDENTOUT])
    SELECT
        CAST(s.[BASCIA] AS INT),
        CAST(s.[NUMBOLET] AS INT),
        TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(NULLIF(s.[FECHAGEN], 0) AS BIGINT))),
        CAST(s.[HORAGEN] AS INT),
        CAST(s.[BASCUSER] AS INT),
        CAST(NULLIF(s.[NUMENVIO], 0) AS INT),
        CAST(s.[BOLETY] AS INT),
        NULLIF(LTRIM(RTRIM(s.[NUMPLACA])), ''),
        NULLIF(LTRIM(RTRIM(s.[MOTORITA])), ''),
        CAST(NULLIF(s.[ORIGEN], 0) AS INT),
        CAST(NULLIF(s.[NUMLUGAR], 0) AS INT),
        CAST(s.[PESOGEMAN] AS DECIMAL(15,0)),
        CAST(s.[PESOTARA] AS DECIMAL(15,0)),
        TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(NULLIF(s.[FECHATAR], 0) AS BIGINT))),
        CASE WHEN s.[HORATARA] IS NULL OR s.[HORATARA] = 0 THEN NULL WHEN s.[HORATARA] < 2400 THEN TRY_CONVERT(TIME(0), STUFF(RIGHT('0000' + CONVERT(VARCHAR(6), CAST(s.[HORATARA] AS INT)), 4), 3, 0, ':')) ELSE TRY_CONVERT(TIME(0), STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(6), CAST(s.[HORATARA] AS INT)), 6), 3, 0, ':'), 6, 0, ':')) END,
        CAST(s.[PESOBRUT] AS DECIMAL(15,0)),
        TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(NULLIF(s.[FECHBRUT], 0) AS BIGINT))),
        CASE WHEN s.[HORABRUT] IS NULL OR s.[HORABRUT] = 0 THEN NULL WHEN s.[HORABRUT] < 2400 THEN TRY_CONVERT(TIME(0), STUFF(RIGHT('0000' + CONVERT(VARCHAR(6), CAST(s.[HORABRUT] AS INT)), 4), 3, 0, ':')) ELSE TRY_CONVERT(TIME(0), STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(6), CAST(s.[HORABRUT] AS INT)), 6), 3, 0, ':'), 6, 0, ':')) END,
        CAST(s.[PESONETO] AS DECIMAL(15,0)),
        CAST(s.[DIFPESO] AS DECIMAL(15,0)),
        NULLIF(LTRIM(RTRIM(s.[RIMPRESO])), ''),
        NULLIF(LTRIM(RTRIM(s.[ESTATUS])), ''),
        CAST(NULLIF(s.[NUMPROD], 0) AS INT),
        CAST(NULLIF(s.[NUMPROV], 0) AS INT),
        NULLIF(LTRIM(RTRIM(s.[MARCHAMO])), ''),
        NULLIF(LTRIM(RTRIM(s.[OBSERBA])), ''),
        NULLIF(LTRIM(RTRIM(s.[NUMDOCTS])), ''),
        CAST(s.[PESOAUDI] AS DECIMAL(15,0)),
        NULLIF(LTRIM(RTRIM(s.[BASAUDIT])), ''),
        NULLIF(LTRIM(RTRIM(s.[MONTAR1])), ''),
        NULLIF(LTRIM(RTRIM(s.[MONTAR2])), ''),
        NULLIF(LTRIM(RTRIM(s.[MONTAR3])), ''),
        NULLIF(LTRIM(RTRIM(s.[MOMBRU1])), ''),
        NULLIF(LTRIM(RTRIM(s.[MOMBRU2])), ''),
        NULLIF(LTRIM(RTRIM(s.[MOMBRU3])), ''),
        TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(NULLIF(s.[FECHATAR1], 0) AS BIGINT))),
        CASE WHEN s.[HORATARA1] IS NULL OR s.[HORATARA1] = 0 THEN NULL WHEN s.[HORATARA1] < 2400 THEN TRY_CONVERT(TIME(0), STUFF(RIGHT('0000' + CONVERT(VARCHAR(6), CAST(s.[HORATARA1] AS INT)), 4), 3, 0, ':')) ELSE TRY_CONVERT(TIME(0), STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(6), CAST(s.[HORATARA1] AS INT)), 6), 3, 0, ':'), 6, 0, ':')) END,
        CAST(s.[PESOTARA1] AS DECIMAL(15,0)),
        TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(NULLIF(s.[FECHATAR2], 0) AS BIGINT))),
        CASE WHEN s.[HORATARA2] IS NULL OR s.[HORATARA2] = 0 THEN NULL WHEN s.[HORATARA2] < 2400 THEN TRY_CONVERT(TIME(0), STUFF(RIGHT('0000' + CONVERT(VARCHAR(6), CAST(s.[HORATARA2] AS INT)), 4), 3, 0, ':')) ELSE TRY_CONVERT(TIME(0), STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(6), CAST(s.[HORATARA2] AS INT)), 6), 3, 0, ':'), 6, 0, ':')) END,
        CAST(s.[PESOTARA2] AS DECIMAL(15,0)),
        TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(NULLIF(s.[FECHATAR3], 0) AS BIGINT))),
        CASE WHEN s.[HORATARA3] IS NULL OR s.[HORATARA3] = 0 THEN NULL WHEN s.[HORATARA3] < 2400 THEN TRY_CONVERT(TIME(0), STUFF(RIGHT('0000' + CONVERT(VARCHAR(6), CAST(s.[HORATARA3] AS INT)), 4), 3, 0, ':')) ELSE TRY_CONVERT(TIME(0), STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(6), CAST(s.[HORATARA3] AS INT)), 6), 3, 0, ':'), 6, 0, ':')) END,
        CAST(s.[PESOTARA3] AS DECIMAL(15,0)),
        TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(NULLIF(s.[FECHBRUT1], 0) AS BIGINT))),
        CASE WHEN s.[HORABRUT1] IS NULL OR s.[HORABRUT1] = 0 THEN NULL WHEN s.[HORABRUT1] < 2400 THEN TRY_CONVERT(TIME(0), STUFF(RIGHT('0000' + CONVERT(VARCHAR(6), CAST(s.[HORABRUT1] AS INT)), 4), 3, 0, ':')) ELSE TRY_CONVERT(TIME(0), STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(6), CAST(s.[HORABRUT1] AS INT)), 6), 3, 0, ':'), 6, 0, ':')) END,
        CAST(s.[PESOBRUT1] AS DECIMAL(15,0)),
        TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(NULLIF(s.[FECHBRUT2], 0) AS BIGINT))),
        CASE WHEN s.[HORABRUT2] IS NULL OR s.[HORABRUT2] = 0 THEN NULL WHEN s.[HORABRUT2] < 2400 THEN TRY_CONVERT(TIME(0), STUFF(RIGHT('0000' + CONVERT(VARCHAR(6), CAST(s.[HORABRUT2] AS INT)), 4), 3, 0, ':')) ELSE TRY_CONVERT(TIME(0), STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(6), CAST(s.[HORABRUT2] AS INT)), 6), 3, 0, ':'), 6, 0, ':')) END,
        CAST(s.[PESOBRUT2] AS DECIMAL(15,0)),
        TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(NULLIF(s.[FECHBRUT3], 0) AS BIGINT))),
        CASE WHEN s.[HORABRUT3] IS NULL OR s.[HORABRUT3] = 0 THEN NULL WHEN s.[HORABRUT3] < 2400 THEN TRY_CONVERT(TIME(0), STUFF(RIGHT('0000' + CONVERT(VARCHAR(6), CAST(s.[HORABRUT3] AS INT)), 4), 3, 0, ':')) ELSE TRY_CONVERT(TIME(0), STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(6), CAST(s.[HORABRUT3] AS INT)), 6), 3, 0, ':'), 6, 0, ':')) END,
        CAST(s.[PESOBRUT3] AS DECIMAL(15,0)),
        CAST(s.[PESOGEMAN1] AS DECIMAL(15,0)),
        CAST(s.[PESOGEMAN2] AS DECIMAL(15,0)),
        CAST(s.[PESOGEMAN3] AS DECIMAL(15,0)),
        CAST(s.[PESONETO1] AS DECIMAL(15,0)),
        CAST(s.[PESONETO2] AS DECIMAL(15,0)),
        CAST(s.[PESONETO3] AS DECIMAL(15,0)),
        CAST(s.[DIFPESO1] AS DECIMAL(15,0)),
        CAST(s.[DIFPESO2] AS DECIMAL(15,0)),
        CAST(s.[DIFPESO3] AS DECIMAL(15,0)),
        NULLIF(LTRIM(RTRIM(s.[MARCACAM])), ''),
        NULLIF(LTRIM(RTRIM(s.[COLORCAM])), ''),
        NULLIF(LTRIM(RTRIM(s.[NUMDOCTO])), ''),
        TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(NULLIF(s.[FECDCTOO], 0) AS BIGINT))),
        NULLIF(LTRIM(RTRIM(s.[STATUS1])), ''),
        NULLIF(LTRIM(RTRIM(s.[STATUS2])), ''),
        NULLIF(LTRIM(RTRIM(s.[ENCARGADO])), ''),
        NULLIF(LTRIM(RTRIM(s.[ONLINE])), ''),
        NULLIF(LTRIM(RTRIM(s.[IDENTIN])), ''),
        NULLIF(LTRIM(RTRIM(s.[IDENTOUT])), '')
    FROM stg.factBasculaBufalo s
    WHERE s.[BASCIA] IS NOT NULL AND s.[NUMBOLET] IS NOT NULL AND s.[HORAGEN] IS NOT NULL;

    DECLARE @FilasSinFecha INT = (SELECT COUNT(*) FROM #Normalizado WHERE FECHAGEN IS NULL);

    ;WITH Numerado AS (
        SELECT n.*,
               COUNT(*) OVER (PARTITION BY BASCIA, NUMBOLET, FECHAGEN, HORAGEN) AS Repeticiones,
               ROW_NUMBER() OVER (PARTITION BY BASCIA, NUMBOLET, FECHAGEN, HORAGEN
                                  ORDER BY FECHBRUT DESC, HORABRUT DESC, PESOBRUT DESC, NUMPLACA) AS rn
        FROM #Normalizado n
        WHERE n.FECHAGEN IS NOT NULL
    ),
    Unico AS (
        SELECT [BASCIA], [NUMBOLET], [FECHAGEN], [HORAGEN], [BASCUSER], [NUMENVIO], [BOLETY], [NUMPLACA], [MOTORITA], [ORIGEN], [NUMLUGAR], [PESOGEMAN], [PESOTARA], [FECHATAR], [HORATARA], [PESOBRUT], [FECHBRUT], [HORABRUT], [PESONETO], [DIFPESO], [RIMPRESO], [ESTATUS], [NUMPROD], [NUMPROV], [MARCHAMO], [OBSERBA], [NUMDOCTS], [PESOAUDI], [BASAUDIT], [MONTAR1], [MONTAR2], [MONTAR3], [MOMBRU1], [MOMBRU2], [MOMBRU3], [FECHATAR1], [HORATARA1], [PESOTARA1], [FECHATAR2], [HORATARA2], [PESOTARA2], [FECHATAR3], [HORATARA3], [PESOTARA3], [FECHBRUT1], [HORABRUT1], [PESOBRUT1], [FECHBRUT2], [HORABRUT2], [PESOBRUT2], [FECHBRUT3], [HORABRUT3], [PESOBRUT3], [PESOGEMAN1], [PESOGEMAN2], [PESOGEMAN3], [PESONETO1], [PESONETO2], [PESONETO3], [DIFPESO1], [DIFPESO2], [DIFPESO3], [MARCACAM], [COLORCAM], [NUMDOCTO], [FECDCTOO], [STATUS1], [STATUS2], [ENCARGADO], [ONLINE], [IDENTIN], [IDENTOUT], Repeticiones FROM Numerado WHERE rn = 1
    )
    SELECT u.*, HASHBYTES('SHA2_256', (SELECT u.* FOR XML RAW, BINARY BASE64)) AS HashDiff
    INTO #Origen
    FROM Unico u;

    CREATE UNIQUE CLUSTERED INDEX IX_Origen ON #Origen (BASCIA, NUMBOLET, FECHAGEN, HORAGEN);
    DECLARE @Llaves INT = (SELECT COUNT(*) FROM #Origen);

    DECLARE @Bajas INT = (
        SELECT COUNT(*) FROM [int].factBasculaBufalo d
        WHERE d.EsVigente = 1
          AND (@VentanaDesde IS NULL OR d.FECHAGEN >= @VentanaDesde)
          AND NOT EXISTS (SELECT 1 FROM #Origen o
                          WHERE o.BASCIA = d.BASCIA AND o.NUMBOLET = d.NUMBOLET
                            AND o.FECHAGEN = d.FECHAGEN AND o.HORAGEN = d.HORAGEN)
    );
    IF @Bajas > @MaxBajas
    BEGIN
        DECLARE @Msg NVARCHAR(400) = CONCAT(N'La corrida daria de baja ', @Bajas, N' boletas (limite ', @MaxBajas,
            N'): se aborta sin cambios. Revisar el extract; si las bajas son reales, correr silver con --max-bajas.');
        THROW 50003, @Msg, 1;
    END

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL, EsVigente BIT NULL);

    MERGE [int].factBasculaBufalo AS destino
        USING #Origen AS origen
        ON  destino.BASCIA = origen.BASCIA AND destino.NUMBOLET = origen.NUMBOLET
        AND destino.FECHAGEN = origen.FECHAGEN AND destino.HORAGEN = origen.HORAGEN
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff OR destino.EsVigente = 0) THEN
        UPDATE SET
            [BASCUSER]   = origen.[BASCUSER],
            [NUMENVIO]   = origen.[NUMENVIO],
            [BOLETY]     = origen.[BOLETY],
            [NUMPLACA]   = origen.[NUMPLACA],
            [MOTORITA]   = origen.[MOTORITA],
            [ORIGEN]     = origen.[ORIGEN],
            [NUMLUGAR]   = origen.[NUMLUGAR],
            [PESOGEMAN]  = origen.[PESOGEMAN],
            [PESOTARA]   = origen.[PESOTARA],
            [FECHATAR]   = origen.[FECHATAR],
            [HORATARA]   = origen.[HORATARA],
            [PESOBRUT]   = origen.[PESOBRUT],
            [FECHBRUT]   = origen.[FECHBRUT],
            [HORABRUT]   = origen.[HORABRUT],
            [PESONETO]   = origen.[PESONETO],
            [DIFPESO]    = origen.[DIFPESO],
            [RIMPRESO]   = origen.[RIMPRESO],
            [ESTATUS]    = origen.[ESTATUS],
            [NUMPROD]    = origen.[NUMPROD],
            [NUMPROV]    = origen.[NUMPROV],
            [MARCHAMO]   = origen.[MARCHAMO],
            [OBSERBA]    = origen.[OBSERBA],
            [NUMDOCTS]   = origen.[NUMDOCTS],
            [PESOAUDI]   = origen.[PESOAUDI],
            [BASAUDIT]   = origen.[BASAUDIT],
            [MONTAR1]    = origen.[MONTAR1],
            [MONTAR2]    = origen.[MONTAR2],
            [MONTAR3]    = origen.[MONTAR3],
            [MOMBRU1]    = origen.[MOMBRU1],
            [MOMBRU2]    = origen.[MOMBRU2],
            [MOMBRU3]    = origen.[MOMBRU3],
            [FECHATAR1]  = origen.[FECHATAR1],
            [HORATARA1]  = origen.[HORATARA1],
            [PESOTARA1]  = origen.[PESOTARA1],
            [FECHATAR2]  = origen.[FECHATAR2],
            [HORATARA2]  = origen.[HORATARA2],
            [PESOTARA2]  = origen.[PESOTARA2],
            [FECHATAR3]  = origen.[FECHATAR3],
            [HORATARA3]  = origen.[HORATARA3],
            [PESOTARA3]  = origen.[PESOTARA3],
            [FECHBRUT1]  = origen.[FECHBRUT1],
            [HORABRUT1]  = origen.[HORABRUT1],
            [PESOBRUT1]  = origen.[PESOBRUT1],
            [FECHBRUT2]  = origen.[FECHBRUT2],
            [HORABRUT2]  = origen.[HORABRUT2],
            [PESOBRUT2]  = origen.[PESOBRUT2],
            [FECHBRUT3]  = origen.[FECHBRUT3],
            [HORABRUT3]  = origen.[HORABRUT3],
            [PESOBRUT3]  = origen.[PESOBRUT3],
            [PESOGEMAN1] = origen.[PESOGEMAN1],
            [PESOGEMAN2] = origen.[PESOGEMAN2],
            [PESOGEMAN3] = origen.[PESOGEMAN3],
            [PESONETO1]  = origen.[PESONETO1],
            [PESONETO2]  = origen.[PESONETO2],
            [PESONETO3]  = origen.[PESONETO3],
            [DIFPESO1]   = origen.[DIFPESO1],
            [DIFPESO2]   = origen.[DIFPESO2],
            [DIFPESO3]   = origen.[DIFPESO3],
            [MARCACAM]   = origen.[MARCACAM],
            [COLORCAM]   = origen.[COLORCAM],
            [NUMDOCTO]   = origen.[NUMDOCTO],
            [FECDCTOO]   = origen.[FECDCTOO],
            [STATUS1]    = origen.[STATUS1],
            [STATUS2]    = origen.[STATUS2],
            [ENCARGADO]  = origen.[ENCARGADO],
            [ONLINE]     = origen.[ONLINE],
            [IDENTIN]    = origen.[IDENTIN],
            [IDENTOUT]   = origen.[IDENTOUT],
            Repeticiones = origen.Repeticiones,
            EsVigente    = 1,
            HashDiff     = origen.HashDiff,
            FechaUltimoCambio = SYSDATETIME(),
            FechaCargaInt = SYSDATETIME(),
            RunId        = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT ([BASCIA], [NUMBOLET], [FECHAGEN], [HORAGEN], [BASCUSER], [NUMENVIO], [BOLETY], [NUMPLACA], [MOTORITA], [ORIGEN], [NUMLUGAR], [PESOGEMAN], [PESOTARA], [FECHATAR], [HORATARA], [PESOBRUT], [FECHBRUT], [HORABRUT], [PESONETO], [DIFPESO], [RIMPRESO], [ESTATUS], [NUMPROD], [NUMPROV], [MARCHAMO], [OBSERBA], [NUMDOCTS], [PESOAUDI], [BASAUDIT], [MONTAR1], [MONTAR2], [MONTAR3], [MOMBRU1], [MOMBRU2], [MOMBRU3], [FECHATAR1], [HORATARA1], [PESOTARA1], [FECHATAR2], [HORATARA2], [PESOTARA2], [FECHATAR3], [HORATARA3], [PESOTARA3], [FECHBRUT1], [HORABRUT1], [PESOBRUT1], [FECHBRUT2], [HORABRUT2], [PESOBRUT2], [FECHBRUT3], [HORABRUT3], [PESOBRUT3], [PESOGEMAN1], [PESOGEMAN2], [PESOGEMAN3], [PESONETO1], [PESONETO2], [PESONETO3], [DIFPESO1], [DIFPESO2], [DIFPESO3], [MARCACAM], [COLORCAM], [NUMDOCTO], [FECDCTOO], [STATUS1], [STATUS2], [ENCARGADO], [ONLINE], [IDENTIN], [IDENTOUT], Repeticiones, HashDiff, RunId)
        VALUES (origen.[BASCIA], origen.[NUMBOLET], origen.[FECHAGEN], origen.[HORAGEN], origen.[BASCUSER], origen.[NUMENVIO], origen.[BOLETY], origen.[NUMPLACA], origen.[MOTORITA], origen.[ORIGEN], origen.[NUMLUGAR], origen.[PESOGEMAN], origen.[PESOTARA], origen.[FECHATAR], origen.[HORATARA], origen.[PESOBRUT], origen.[FECHBRUT], origen.[HORABRUT], origen.[PESONETO], origen.[DIFPESO], origen.[RIMPRESO], origen.[ESTATUS], origen.[NUMPROD], origen.[NUMPROV], origen.[MARCHAMO], origen.[OBSERBA], origen.[NUMDOCTS], origen.[PESOAUDI], origen.[BASAUDIT], origen.[MONTAR1], origen.[MONTAR2], origen.[MONTAR3], origen.[MOMBRU1], origen.[MOMBRU2], origen.[MOMBRU3], origen.[FECHATAR1], origen.[HORATARA1], origen.[PESOTARA1], origen.[FECHATAR2], origen.[HORATARA2], origen.[PESOTARA2], origen.[FECHATAR3], origen.[HORATARA3], origen.[PESOTARA3], origen.[FECHBRUT1], origen.[HORABRUT1], origen.[PESOBRUT1], origen.[FECHBRUT2], origen.[HORABRUT2], origen.[PESOBRUT2], origen.[FECHBRUT3], origen.[HORABRUT3], origen.[PESOBRUT3], origen.[PESOGEMAN1], origen.[PESOGEMAN2], origen.[PESOGEMAN3], origen.[PESONETO1], origen.[PESONETO2], origen.[PESONETO3], origen.[DIFPESO1], origen.[DIFPESO2], origen.[DIFPESO3], origen.[MARCACAM], origen.[COLORCAM], origen.[NUMDOCTO], origen.[FECDCTOO], origen.[STATUS1], origen.[STATUS2], origen.[ENCARGADO], origen.[ONLINE], origen.[IDENTIN], origen.[IDENTOUT], origen.Repeticiones, origen.HashDiff, @RunId)
    WHEN NOT MATCHED BY SOURCE AND destino.EsVigente = 1
                              AND (@VentanaDesde IS NULL OR destino.FECHAGEN >= @VentanaDesde) THEN
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
        @FilasLeidas - @Llaves - @FilasSinFecha AS FilasRepetidas,
        @FilasSinFecha                 AS FilasSinFecha;

    DROP TABLE #Origen;
END
GO

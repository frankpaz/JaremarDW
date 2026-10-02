-- 247: merge Bronze -> Silver de factEnvios con carga incremental por huella (migracion 246).
-- stg.factEnvios ya no trae toda la tabla: trae los dias que no cuadraron (listados en
-- stg.factEnvios_Periodos) mas los envios de [int] de esos dias que ya no estaban en ellos
-- pero siguen existiendo en el AS400 con otra fecha (el extract los busca por ENCENV).
--   llave nueva                          -> INSERT
--   HashDiff o huella distinta           -> UPDATE (la huella tambien, para que el dia cuadre)
--   vigente de un dia revisado, ausente  -> EsVigente = 0 (nunca se borra)
-- Resguardo: si daria de baja mas de @MaxBajas envios aborta sin tocar nada.
-- Dedup por ENCENV igual que la 101 (el duplicado legitimo es doble pesaje el mismo dia: se
-- conserva el mas reciente por hora), pero Repeticiones y HuellaOrigen suman todas sus filas.
-- ENCFEC/ENCFEU (DECIMAL YYYYMMDD) -> DATE. ENCTIM/ENCTIU (DECIMAL HHMMSSHH) -> TIME(0).
-- Compatible con SQL Server 2016.

-- stg la auto-provisiona el extract, pero el procedimiento no compila si stg.factEnvios ya
-- existe sin HUELLA. Se agrega aqui con el mismo tipo que usa el extract (BIGINT NULL); queda al
-- final de la tabla, lo que no importa: el extract compara el conjunto de columnas, no el orden.
IF OBJECT_ID('stg.factEnvios') IS NOT NULL AND COL_LENGTH('stg.factEnvios', 'HUELLA') IS NULL
    ALTER TABLE stg.factEnvios ADD HUELLA BIGINT NULL;
GO

CREATE OR ALTER PROCEDURE [int].usp_MergeFactEnvios
    @RunId     INT,
    @MaxBajas  INT = 200
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.factEnvios);

    ;WITH StgDeduplicado AS (
        SELECT s.*,
               ROW_NUMBER() OVER (PARTITION BY s.ENCENV ORDER BY s.ENCFEC DESC, s.ENCTIM DESC) AS rn,
               COUNT(*) OVER (PARTITION BY s.ENCENV) AS Repeticiones,
               SUM(CAST(s.HUELLA AS DECIMAL(30,0))) OVER (PARTITION BY s.ENCENV) AS HuellaOrigen
        FROM stg.factEnvios s
        WHERE s.ENCENV IS NOT NULL AND s.ENCENV <> 0
    ),
    StgNormalizado AS (
        SELECT
            s.ENCENV                                                       AS ENCENV,
            NULLIF(RTRIM(s.ENCUSU), '')                                    AS ENCUSU,
            NULLIF(RTRIM(s.ENCDSP), '')                                    AS ENCDSP,
            TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(s.ENCFEC AS BIGINT)))  AS ENCFEC,
            TRY_CONVERT(TIME(0), STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(6), CAST(s.ENCTIM AS BIGINT) / 100), 6), 3, 0, ':'), 6, 0, ':')) AS ENCTIM,
            NULLIF(RTRIM(s.ENCCAM), '')                                    AS ENCCAM,
            s.ENCPEC                                                       AS ENCPEC,
            NULLIF(RTRIM(s.ENCCAD), '')                                    AS ENCCAD,
            s.ENCEMT                                                       AS ENCEMT,
            NULLIF(RTRIM(s.ENCEMN), '')                                    AS ENCEMN,
            s.ENCEN1                                                       AS ENCEN1,
            NULLIF(RTRIM(s.ENCED1), '')                                    AS ENCED1,
            s.ENCEN2                                                       AS ENCEN2,
            NULLIF(RTRIM(s.ENCED2), '')                                    AS ENCED2,
            s.ENCEN3                                                       AS ENCEN3,
            NULLIF(RTRIM(s.ENCED3), '')                                    AS ENCED3,
            s.ENCEN4                                                       AS ENCEN4,
            NULLIF(RTRIM(s.ENCED4), '')                                    AS ENCED4,
            NULLIF(RTRIM(s.ENCROU), '')                                    AS ENCROU,
            NULLIF(RTRIM(s.ENCDER), '')                                    AS ENCDER,
            TRY_CONVERT(DATE, CONVERT(CHAR(8), CAST(s.ENCFEU AS BIGINT)))  AS ENCFEU,
            TRY_CONVERT(TIME(0), STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(6), CAST(s.ENCTIU AS BIGINT) / 100), 6), 3, 0, ':'), 6, 0, ':')) AS ENCTIU,
            NULLIF(RTRIM(s.ENCSTA), '')                                    AS ENCSTA,
            s.ENCPES                                                       AS ENCPES,
            NULLIF(RTRIM(s.ENCPLA), '')                                    AS ENCPLA,
            NULLIF(RTRIM(s.ENCDT1), '')                                    AS ENCDT1,
            NULLIF(RTRIM(s.ENCPT2), '')                                    AS ENCPT2,
            s.ENCFEC                                                       AS PeriodoOrigen,
            s.Repeticiones                                                 AS Repeticiones,
            s.HuellaOrigen                                                 AS HuellaOrigen
        FROM StgDeduplicado s
        WHERE s.rn = 1
    )
    SELECT n.*,
           -- El HashDiff se calcula sin las columnas de control, igual que en la 101.
           HASHBYTES('SHA2_256', (
               SELECT n.ENCENV, n.ENCUSU, n.ENCDSP, n.ENCFEC, n.ENCTIM, n.ENCCAM, n.ENCPEC, n.ENCCAD,
                      n.ENCEMT, n.ENCEMN, n.ENCEN1, n.ENCED1, n.ENCEN2, n.ENCED2, n.ENCEN3, n.ENCED3,
                      n.ENCEN4, n.ENCED4, n.ENCROU, n.ENCDER, n.ENCFEU, n.ENCTIU, n.ENCSTA, n.ENCPES,
                      n.ENCPLA, n.ENCDT1, n.ENCPT2
               FOR XML RAW, BINARY BASE64)) AS HashDiff
    INTO #Origen
    FROM StgNormalizado n;

    CREATE UNIQUE CLUSTERED INDEX IX_Origen ON #Origen (ENCENV);

    DECLARE @Bajas INT = (
        SELECT COUNT(*) FROM [int].factEnvios d
        WHERE d.EsVigente = 1
          AND d.PeriodoOrigen IN (SELECT p.Periodo FROM stg.factEnvios_Periodos p)
          AND NOT EXISTS (SELECT 1 FROM #Origen o WHERE o.ENCENV = d.ENCENV)
    );
    IF @Bajas > @MaxBajas
    BEGIN
        DECLARE @Msg NVARCHAR(400) = CONCAT(N'La corrida daria de baja ', @Bajas, N' envios (limite ', @MaxBajas,
            N'): se aborta sin cambios. Revisar el extract; si las bajas son reales, correr silver con --max-bajas.');
        THROW 50003, @Msg, 1;
    END

    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL, EsVigente BIT NULL);

    MERGE [int].factEnvios AS destino
        USING #Origen AS origen
        ON destino.ENCENV = origen.ENCENV
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff
                      OR destino.EsVigente = 0
                      OR destino.Repeticiones <> origen.Repeticiones
                      OR ISNULL(destino.HuellaOrigen, -1) <> ISNULL(origen.HuellaOrigen, -1)
                      OR ISNULL(destino.PeriodoOrigen, -1) <> ISNULL(origen.PeriodoOrigen, -1)) THEN
        UPDATE SET
            ENCUSU        = origen.ENCUSU,
            ENCDSP        = origen.ENCDSP,
            ENCFEC        = origen.ENCFEC,
            ENCTIM        = origen.ENCTIM,
            ENCCAM        = origen.ENCCAM,
            ENCPEC        = origen.ENCPEC,
            ENCCAD        = origen.ENCCAD,
            ENCEMT        = origen.ENCEMT,
            ENCEMN        = origen.ENCEMN,
            ENCEN1        = origen.ENCEN1,
            ENCED1        = origen.ENCED1,
            ENCEN2        = origen.ENCEN2,
            ENCED2        = origen.ENCED2,
            ENCEN3        = origen.ENCEN3,
            ENCED3        = origen.ENCED3,
            ENCEN4        = origen.ENCEN4,
            ENCED4        = origen.ENCED4,
            ENCROU        = origen.ENCROU,
            ENCDER        = origen.ENCDER,
            ENCFEU        = origen.ENCFEU,
            ENCTIU        = origen.ENCTIU,
            ENCSTA        = origen.ENCSTA,
            ENCPES        = origen.ENCPES,
            ENCPLA        = origen.ENCPLA,
            ENCDT1        = origen.ENCDT1,
            ENCPT2        = origen.ENCPT2,
            PeriodoOrigen = origen.PeriodoOrigen,
            Repeticiones  = origen.Repeticiones,
            HuellaOrigen  = origen.HuellaOrigen,
            EsVigente     = 1,
            HashDiff      = origen.HashDiff,
            FechaCargaInt = SYSDATETIME(),
            RunId         = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (
            ENCENV, ENCUSU, ENCDSP, ENCFEC, ENCTIM, ENCCAM, ENCPEC, ENCCAD, ENCEMT, ENCEMN,
            ENCEN1, ENCED1, ENCEN2, ENCED2, ENCEN3, ENCED3, ENCEN4, ENCED4,
            ENCROU, ENCDER, ENCFEU, ENCTIU, ENCSTA, ENCPES, ENCPLA, ENCDT1, ENCPT2,
            PeriodoOrigen, Repeticiones, HuellaOrigen, HashDiff, RunId
        )
        VALUES (
            origen.ENCENV, origen.ENCUSU, origen.ENCDSP, origen.ENCFEC, origen.ENCTIM, origen.ENCCAM, origen.ENCPEC, origen.ENCCAD, origen.ENCEMT, origen.ENCEMN,
            origen.ENCEN1, origen.ENCED1, origen.ENCEN2, origen.ENCED2, origen.ENCEN3, origen.ENCED3, origen.ENCEN4, origen.ENCED4,
            origen.ENCROU, origen.ENCDER, origen.ENCFEU, origen.ENCTIU, origen.ENCSTA, origen.ENCPES, origen.ENCPLA, origen.ENCDT1, origen.ENCPT2,
            origen.PeriodoOrigen, origen.Repeticiones, origen.HuellaOrigen, origen.HashDiff, @RunId
        )
    WHEN NOT MATCHED BY SOURCE AND destino.EsVigente = 1
                              AND destino.PeriodoOrigen IN (SELECT p.Periodo FROM stg.factEnvios_Periodos p) THEN
        UPDATE SET EsVigente = 0, FechaCargaInt = SYSDATETIME(), RunId = @RunId
    OUTPUT $action, inserted.EsVigente INTO #AccionesMerge;

    SELECT
        @FilasLeidas                                                                         AS FilasLeidas,
        ISNULL(SUM(CASE WHEN Accion = 'INSERT' THEN 1 ELSE 0 END), 0)                        AS FilasInsertadas,
        ISNULL(SUM(CASE WHEN Accion = 'UPDATE' AND EsVigente = 1 THEN 1 ELSE 0 END), 0)      AS FilasActualizadas,
        @FilasLeidas - ISNULL(SUM(CASE WHEN Accion = 'INSERT' THEN 1 ELSE 0 END), 0)
                      - ISNULL(SUM(CASE WHEN Accion = 'UPDATE' AND EsVigente = 1 THEN 1 ELSE 0 END), 0) AS FilasIgnoradas,
        ISNULL(SUM(CASE WHEN Accion = 'UPDATE' AND EsVigente = 0 THEN 1 ELSE 0 END), 0)      AS FilasDadasDeBaja
    FROM #AccionesMerge;
END
GO

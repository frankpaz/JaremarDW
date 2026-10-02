-- 249: merge Bronze -> Silver de factCompras con carga incremental por huella (estructura en la 248).
-- stg ya no trae una ventana de fechas: trae
--   * encabezados: todos los de los dias de factura (AINVDT) que no cuadraron
--     (stg.factComprasEncabezados_Periodos), mas los que necesiten las lineas traidas;
--   * lineas: todas las de los dias de creacion (PLEDTE) que no cuadraron
--     (stg.factComprasLineas_Periodos) y las de los encabezados que cambiaron (para refrescar sus
--     datos de encabezado).
-- Pasos:
--   1. Control de encabezados: MERGE por compania+prefijo+anio+secuencia+proveedor+factura;
--      los vigentes de un dia revisado que ya no estan en el AS400 -> EsVigente = 0.
--   2. Lineas: cada linea toma su encabezado por compania+prefijo+anio+secuencia+proveedor+
--      factura; si no lo encuentra y el documento tiene un solo encabezado, toma ese (4 lineas
--      recapturadas con otro signo en el numero de factura). Los encabezados de secuencia 0 que
--      comparten documento ya no se mezclan.
--   3. MERGE por documento+linea+proveedor+factura+fecha de creacion (PeriodoOrigen): inserta,
--      actualiza si cambia el HashDiff o la huella, y da de baja (EsVigente = 0, nunca borra) las
--      lineas vigentes de un dia revisado que ya no estan en el AS400. La fecha es parte de la
--      llave porque el ERP recaptura algunas lineas otro dia con la misma llave (91 casos).
-- Resguardo: si daria de baja mas de @MaxBajas lineas o encabezados, aborta sin tocar nada.
-- El HashDiff se calcula sobre las mismas 34 columnas y en el mismo orden que la 117, para que
-- las filas existentes no se marquen como cambiadas solo por el cambio de procedimiento.
-- Compatible con SQL Server 2016.

CREATE OR ALTER PROCEDURE [int].usp_MergeFactCompras
    @RunId     INT,
    @MaxBajas  INT = 200
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FilasLeidas INT = (SELECT COUNT(*) FROM stg.factComprasLineas);

    -- 1. Encabezados de stg, uno por llave -----------------------------------------------
    ;WITH Enc AS (
        SELECT
            e.APCMPY, e.PHDCPX, e.PHDCYR, e.PHDCSQ,
            ISNULL(e.APVNDR, 0)                AS APVNDR,
            ISNULL(RTRIM(e.APINV), N'')        AS APINV,
            e.AINVDT                           AS PeriodoOrigen,
            e.APHPND, e.APHBNK, e.APHCUR, e.APHOLD, e.AINVDT, e.ADUEDT, e.ADISCD,
            e.APCINA, e.APCAMP, e.APCOUT, e.APPORD, e.APTERM, e.APSTAT, e.APPAYS,
            e.PHHTRT, e.PHTXBA, e.APVNTX, e.APPAYT,
            ROW_NUMBER() OVER (PARTITION BY e.APCMPY, e.PHDCPX, e.PHDCYR, e.PHDCSQ, ISNULL(e.APVNDR, 0), ISNULL(RTRIM(e.APINV), N'')
                               ORDER BY e.AINVDT DESC) AS rn,
            COUNT(*) OVER (PARTITION BY e.APCMPY, e.PHDCPX, e.PHDCYR, e.PHDCSQ, ISNULL(e.APVNDR, 0), ISNULL(RTRIM(e.APINV), N'')) AS Repeticiones,
            SUM(CAST(e.HUELLA AS DECIMAL(30,0))) OVER (PARTITION BY e.APCMPY, e.PHDCPX, e.PHDCYR, e.PHDCSQ, ISNULL(e.APVNDR, 0), ISNULL(RTRIM(e.APINV), N'')) AS HuellaOrigen
        FROM stg.factComprasEncabezados e
        WHERE e.APCMPY IS NOT NULL
    )
    SELECT *, COUNT(*) OVER (PARTITION BY APCMPY, PHDCPX, PHDCYR, PHDCSQ) AS EncabezadosDocumento
    INTO #Enc
    FROM Enc WHERE rn = 1;

    CREATE UNIQUE CLUSTERED INDEX IX_Enc ON #Enc (APCMPY, PHDCPX, PHDCYR, PHDCSQ, APVNDR, APINV);

    -- 2. Lineas de stg, una por llave, con su encabezado -------------------------------------
    ;WITH Lin AS (
        SELECT l.*,
               ROW_NUMBER() OVER (PARTITION BY l.PLCMPY, l.PLDCPX, l.PLDCYR, l.PLDCSQ, l.PLLINE, ISNULL(l.PLVNDR, -1), ISNULL(NULLIF(RTRIM(l.PLINV), ''), N''), l.PLEDTE
                                  ORDER BY l.PLEDTE DESC, l.PLETIM DESC) AS rn,
               COUNT(*) OVER (PARTITION BY l.PLCMPY, l.PLDCPX, l.PLDCYR, l.PLDCSQ, l.PLLINE, ISNULL(l.PLVNDR, -1), ISNULL(NULLIF(RTRIM(l.PLINV), ''), N''), l.PLEDTE) AS Repeticiones,
               SUM(CAST(l.HUELLA AS DECIMAL(30,0))) OVER (PARTITION BY l.PLCMPY, l.PLDCPX, l.PLDCYR, l.PLDCSQ, l.PLLINE, ISNULL(l.PLVNDR, -1), ISNULL(NULLIF(RTRIM(l.PLINV), ''), N''), l.PLEDTE) AS HuellaOrigen
        FROM stg.factComprasLineas l
        WHERE l.PLCMPY IS NOT NULL
    ),
    LinConEncabezado AS (
        SELECT
            l.PLCMPY, l.PLDCPX, l.PLDCYR, l.PLDCSQ, l.PLLINE, l.PLVNDR, l.PLINV, l.PLTYPE, l.PLGLDT,
            l.PLAMT, l.PLBAMT, l.PLDESC, l.PLUSER, l.PLEDTE, l.PLETIM, l.PLRESN,
            h.APHPND, h.APHBNK, h.APHCUR, h.APHOLD, h.AINVDT, h.ADUEDT, h.ADISCD, h.APCINA, h.APCAMP,
            h.APCOUT, h.APPORD, h.APTERM, h.APSTAT, h.APPAYS, h.PHHTRT, h.PHTXBA, h.APVNTX, h.APPAYT,
            l.PLEDTE AS PeriodoOrigen, l.Repeticiones, l.HuellaOrigen
        FROM Lin l
        OUTER APPLY (
            SELECT TOP 1 e.*
            FROM #Enc e
            WHERE e.APCMPY = l.PLCMPY AND e.PHDCPX = l.PLDCPX AND e.PHDCYR = l.PLDCYR AND e.PHDCSQ = l.PLDCSQ
              AND ((e.APVNDR = ISNULL(l.PLVNDR, -1) AND e.APINV = ISNULL(RTRIM(l.PLINV), N''))
                   OR e.EncabezadosDocumento = 1)
            ORDER BY CASE WHEN e.APVNDR = ISNULL(l.PLVNDR, -1) AND e.APINV = ISNULL(RTRIM(l.PLINV), N'') THEN 0 ELSE 1 END
        ) h
        WHERE l.rn = 1
    ),
    LinNormalizada AS (
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
            NULLIF(RTRIM(APPAYT), '') AS APPAYT,
            PeriodoOrigen,
            Repeticiones,
            HuellaOrigen
        FROM LinConEncabezado
    )
    SELECT n.*,
           HASHBYTES('SHA2_256', (
               SELECT n.PLCMPY, n.PLDCPX, n.PLDCYR, n.PLDCSQ, n.PLLINE, n.PLVNDR, n.PLINV, n.PLTYPE, n.PLGLDT,
                      n.PLAMT, n.PLBAMT, n.PLDESC, n.PLUSER, n.PLEDTE, n.PLETIM, n.PLRESN, n.APHPND, n.APHBNK,
                      n.APHCUR, n.APHOLD, n.AINVDT, n.ADUEDT, n.ADISCD, n.APCINA, n.APCAMP, n.APCOUT, n.APPORD,
                      n.APTERM, n.APSTAT, n.APPAYS, n.PHHTRT, n.PHTXBA, n.APVNTX, n.APPAYT
               FOR XML RAW, BINARY BASE64)) AS HashDiff
    INTO #Lin
    FROM LinNormalizada n;

    -- 3. Resguardo de bajas ---------------------------------------------------------------
    DECLARE @BajasEncabezados INT = (
        SELECT COUNT(*) FROM [int].factComprasEncabezados c
        WHERE c.EsVigente = 1
          AND c.PeriodoOrigen IN (SELECT p.Periodo FROM stg.factComprasEncabezados_Periodos p)
          AND NOT EXISTS (SELECT 1 FROM #Enc e
                          WHERE e.APCMPY = c.APCMPY AND e.PHDCPX = c.PHDCPX AND e.PHDCYR = c.PHDCYR
                            AND e.PHDCSQ = c.PHDCSQ AND e.APVNDR = c.APVNDR AND e.APINV = c.APINV)
    );
    DECLARE @BajasLineas INT = (
        SELECT COUNT(*) FROM [int].factCompras d
        WHERE d.EsVigente = 1
          AND d.PeriodoOrigen IN (SELECT p.Periodo FROM stg.factComprasLineas_Periodos p)
          AND NOT EXISTS (SELECT 1 FROM #Lin o
                          WHERE o.PLCMPY = d.PLCMPY AND o.PLDCPX = d.PLDCPX AND o.PLDCYR = d.PLDCYR
                            AND o.PLDCSQ = d.PLDCSQ AND o.PLLINE = d.PLLINE
                            AND ISNULL(o.PLVNDR, -1) = ISNULL(d.PLVNDR, -1) AND ISNULL(o.PLINV, N'') = ISNULL(d.PLINV, N'')
                            AND o.PeriodoOrigen = d.PeriodoOrigen)
    );
    IF @BajasEncabezados > @MaxBajas OR @BajasLineas > @MaxBajas
    BEGIN
        DECLARE @Msg NVARCHAR(400) = CONCAT(N'La corrida daria de baja ', @BajasLineas, N' lineas y ', @BajasEncabezados,
            N' encabezados (limite ', @MaxBajas, N'): se aborta sin cambios. Revisar los extracts; si las bajas son reales, correr silver con --max-bajas.');
        THROW 50003, @Msg, 1;
    END

    -- 4. Control de encabezados -----------------------------------------------------------
    MERGE [int].factComprasEncabezados AS destino
        USING #Enc AS origen
        ON destino.APCMPY = origen.APCMPY AND destino.PHDCPX = origen.PHDCPX AND destino.PHDCYR = origen.PHDCYR
       AND destino.PHDCSQ = origen.PHDCSQ AND destino.APVNDR = origen.APVNDR AND destino.APINV = origen.APINV
    WHEN MATCHED AND (destino.EsVigente = 0
                      OR destino.Repeticiones <> origen.Repeticiones
                      OR ISNULL(destino.HuellaOrigen, -1) <> ISNULL(origen.HuellaOrigen, -1)
                      OR ISNULL(destino.PeriodoOrigen, -1) <> ISNULL(origen.PeriodoOrigen, -1)) THEN
        UPDATE SET PeriodoOrigen = origen.PeriodoOrigen, Repeticiones = origen.Repeticiones,
                   HuellaOrigen = origen.HuellaOrigen, EsVigente = 1,
                   FechaCargaInt = SYSDATETIME(), RunId = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (APCMPY, PHDCPX, PHDCYR, PHDCSQ, APVNDR, APINV, PeriodoOrigen, Repeticiones, HuellaOrigen, RunId)
        VALUES (origen.APCMPY, origen.PHDCPX, origen.PHDCYR, origen.PHDCSQ, origen.APVNDR, origen.APINV,
                origen.PeriodoOrigen, origen.Repeticiones, origen.HuellaOrigen, @RunId)
    WHEN NOT MATCHED BY SOURCE AND destino.EsVigente = 1
                              AND destino.PeriodoOrigen IN (SELECT p.Periodo FROM stg.factComprasEncabezados_Periodos p) THEN
        UPDATE SET EsVigente = 0, FechaCargaInt = SYSDATETIME(), RunId = @RunId;

    -- 5. Lineas ---------------------------------------------------------------------------
    CREATE TABLE #AccionesMerge (Accion VARCHAR(20) NOT NULL, EsVigente BIT NULL);

    MERGE [int].factCompras AS destino
        USING #Lin AS origen
        ON destino.PLCMPY = origen.PLCMPY AND destino.PLDCPX = origen.PLDCPX AND destino.PLDCYR = origen.PLDCYR
       AND destino.PLDCSQ = origen.PLDCSQ AND destino.PLLINE = origen.PLLINE
       AND ISNULL(destino.PLVNDR, -1) = ISNULL(origen.PLVNDR, -1) AND ISNULL(destino.PLINV, N'') = ISNULL(origen.PLINV, N'')
       AND ISNULL(destino.PeriodoOrigen, -1) = ISNULL(origen.PeriodoOrigen, -1)
    WHEN MATCHED AND (destino.HashDiff <> origen.HashDiff
                      OR destino.EsVigente = 0
                      OR destino.Repeticiones <> origen.Repeticiones
                      OR ISNULL(destino.HuellaOrigen, -1) <> ISNULL(origen.HuellaOrigen, -1)) THEN
        UPDATE SET
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
            Repeticiones  = origen.Repeticiones,
            HuellaOrigen  = origen.HuellaOrigen,
            EsVigente     = 1,
            HashDiff      = origen.HashDiff,
            FechaCargaInt = SYSDATETIME(),
            RunId         = @RunId
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (PLCMPY, PLDCPX, PLDCYR, PLDCSQ, PLLINE, PLVNDR, PLINV, PLTYPE, PLGLDT, PLAMT, PLBAMT, PLDESC, PLUSER,
                PLEDTE, PLETIM, PLRESN, APHPND, APHBNK, APHCUR, APHOLD, AINVDT, ADUEDT, ADISCD, APCINA, APCAMP,
                APCOUT, APPORD, APTERM, APSTAT, APPAYS, PHHTRT, PHTXBA, APVNTX, APPAYT,
                PeriodoOrigen, Repeticiones, HuellaOrigen, HashDiff, RunId)
        VALUES (origen.PLCMPY, origen.PLDCPX, origen.PLDCYR, origen.PLDCSQ, origen.PLLINE, origen.PLVNDR, origen.PLINV,
                origen.PLTYPE, origen.PLGLDT, origen.PLAMT, origen.PLBAMT, origen.PLDESC, origen.PLUSER, origen.PLEDTE,
                origen.PLETIM, origen.PLRESN, origen.APHPND, origen.APHBNK, origen.APHCUR, origen.APHOLD, origen.AINVDT,
                origen.ADUEDT, origen.ADISCD, origen.APCINA, origen.APCAMP, origen.APCOUT, origen.APPORD, origen.APTERM,
                origen.APSTAT, origen.APPAYS, origen.PHHTRT, origen.PHTXBA, origen.APVNTX, origen.APPAYT,
                origen.PeriodoOrigen, origen.Repeticiones, origen.HuellaOrigen, origen.HashDiff, @RunId)
    WHEN NOT MATCHED BY SOURCE AND destino.EsVigente = 1
                              AND destino.PeriodoOrigen IN (SELECT p.Periodo FROM stg.factComprasLineas_Periodos p) THEN
        UPDATE SET EsVigente = 0, FechaCargaInt = SYSDATETIME(), RunId = @RunId
    OUTPUT $action, inserted.EsVigente INTO #AccionesMerge;

    SELECT
        @FilasLeidas                                                                         AS FilasLeidas,
        ISNULL(SUM(CASE WHEN Accion = 'INSERT' THEN 1 ELSE 0 END), 0)                        AS FilasInsertadas,
        ISNULL(SUM(CASE WHEN Accion = 'UPDATE' AND EsVigente = 1 THEN 1 ELSE 0 END), 0)      AS FilasActualizadas,
        @FilasLeidas - ISNULL(SUM(CASE WHEN Accion = 'INSERT' THEN 1 ELSE 0 END), 0)
                      - ISNULL(SUM(CASE WHEN Accion = 'UPDATE' AND EsVigente = 1 THEN 1 ELSE 0 END), 0) AS FilasIgnoradas,
        ISNULL(SUM(CASE WHEN Accion = 'UPDATE' AND EsVigente = 0 THEN 1 ELSE 0 END), 0)      AS FilasDadasDeBaja,
        @BajasEncabezados                                                                    AS EncabezadosDadosDeBaja
    FROM #AccionesMerge;
END
GO

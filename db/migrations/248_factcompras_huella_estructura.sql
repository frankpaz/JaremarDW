-- 248: factCompras pasa a carga incremental por huella (ver db/etl/huella_as400.py y la 246
-- de factEnvios). Estructura; los procedimientos van en la 249 (silver) y la 250 (gold).
--
-- Discovery del 2026-10-02 (APH/APL contra [int] en PROD):
--   * El encabezado cambia despues de sus lineas (pagos: APCAMP/APSTAT/APCOUT) y la ventana de
--     30 dias por fecha de la linea no lo volvia a leer: 661 encabezados desactualizados.
--   * 479 encabezados con secuencia 0 (PHDCSQ = 0, facturas que no se terminaron de registrar,
--     APSTAT U/V, sin monto) comparten compania+prefijo+anio+secuencia; sus 731 lineas cruzaban
--     con cualquiera. Compania+prefijo+anio+secuencia+proveedor+factura es unico en APH.
--   * 1.302 lineas con PLEDTE = 0 nunca se cargaban (el extract filtraba por esa fecha).
--
-- [int].factCompras:
--   * Llave = documento + linea + proveedor (PLVNDR) + factura (PLINV) + fecha de creacion
--     (PeriodoOrigen = PLEDTE): proveedor y factura recuperan ~428 lineas de secuencia 0 que
--     chocaban; la fecha separa las 91 lineas que el ERP volvio a capturar otro dia con la misma
--     llave (sin ella, sus dos dias nunca cuadrarian). Indice unico (no PK: PLVNDR/PLINV admiten
--     NULL; SQL Server trata los NULL como iguales en un indice unico).
--   * PeriodoOrigen = PLEDTE del AS400 sin convertir (0 para las lineas sin fecha),
--     Repeticiones y HuellaOrigen (las lineas repetidas del mismo dia se guardan una vez y suman
--     sus huellas), EsVigente (bajas logicas; nunca se borra).
-- [int].factComprasEncabezados: control de huellas de TODOS los encabezados PH (con y sin
--   lineas), por dia de factura (AINVDT sin convertir). No guarda los datos del encabezado
--   (esos viven en cada linea de [int].factCompras), solo lo necesario para comparar.
-- stg.factComprasEncabezados_Periodos / stg.factComprasLineas_Periodos: dias que el ultimo
--   extract trajo completos (silver solo da de baja dentro de ellos).
-- stg: APVNDR, APINV y HUELLA en encabezados y HUELLA en lineas (el extract los auto-provisiona;
--   se agregan aqui para que los procedimientos de la 249 compilen).
-- dw.factCompras: EsVigente y la llave unica con proveedor, factura y fecha de creacion.
-- Las filas existentes quedan con HuellaOrigen NULL: la primera corrida completa no cuadra
-- ningun dia y vuelve a traer todo una vez.
-- Idempotente. Compatible con SQL Server 2016.

-- [int].factCompras ----------------------------------------------------------------------
IF COL_LENGTH('[int].factCompras', 'PeriodoOrigen') IS NULL
    ALTER TABLE [int].factCompras ADD PeriodoOrigen DECIMAL(8,0) NULL;
GO
IF COL_LENGTH('[int].factCompras', 'Repeticiones') IS NULL
    ALTER TABLE [int].factCompras ADD Repeticiones INT NOT NULL
        CONSTRAINT DF_Int_factCompras_Repeticiones DEFAULT (1);
GO
IF COL_LENGTH('[int].factCompras', 'HuellaOrigen') IS NULL
    ALTER TABLE [int].factCompras ADD HuellaOrigen DECIMAL(30,0) NULL;
GO
IF COL_LENGTH('[int].factCompras', 'EsVigente') IS NULL
    ALTER TABLE [int].factCompras ADD EsVigente BIT NOT NULL
        CONSTRAINT DF_Int_factCompras_EsVigente DEFAULT (1);
GO

UPDATE [int].factCompras
SET PeriodoOrigen = CONVERT(DECIMAL(8,0), CONVERT(CHAR(8), PLEDTE, 112))
WHERE PeriodoOrigen IS NULL AND PLEDTE IS NOT NULL;
GO

IF EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'PK_Int_factCompras'
           AND parent_object_id = OBJECT_ID('[int].factCompras'))
    ALTER TABLE [int].factCompras DROP CONSTRAINT PK_Int_factCompras;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_Int_factCompras_Llave'
               AND object_id = OBJECT_ID('[int].factCompras'))
    CREATE UNIQUE CLUSTERED INDEX UX_Int_factCompras_Llave
        ON [int].factCompras (PLCMPY, PLDCPX, PLDCYR, PLDCSQ, PLLINE, PLVNDR, PLINV, PeriodoOrigen);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Int_factCompras_PeriodoOrigen'
               AND object_id = OBJECT_ID('[int].factCompras'))
    CREATE INDEX IX_Int_factCompras_PeriodoOrigen ON [int].factCompras (PeriodoOrigen)
        INCLUDE (EsVigente, Repeticiones, HuellaOrigen);
GO

-- [int].factComprasEncabezados (control de huellas) ----------------------------------------
IF OBJECT_ID('[int].factComprasEncabezados') IS NULL
    CREATE TABLE [int].factComprasEncabezados (
        APCMPY          DECIMAL(2,0)   NOT NULL,
        PHDCPX          NVARCHAR(2)    NOT NULL,
        PHDCYR          DECIMAL(2,0)   NOT NULL,
        PHDCSQ          DECIMAL(8,0)   NOT NULL,
        APVNDR          DECIMAL(8,0)   NOT NULL,
        APINV           NVARCHAR(10)   NOT NULL,   -- sin blancos a la derecha ('' si viene vacia)
        PeriodoOrigen   DECIMAL(8,0)   NULL,       -- AINVDT del AS400 sin convertir
        Repeticiones    INT            NOT NULL CONSTRAINT DF_Int_factComprasEncabezados_Repeticiones DEFAULT (1),
        HuellaOrigen    DECIMAL(30,0)  NULL,
        EsVigente       BIT            NOT NULL CONSTRAINT DF_Int_factComprasEncabezados_EsVigente DEFAULT (1),
        FechaCargaInt   DATETIME2(7)   NOT NULL CONSTRAINT DF_Int_factComprasEncabezados_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId           INT            NULL,
        CONSTRAINT PK_Int_factComprasEncabezados PRIMARY KEY (APCMPY, PHDCPX, PHDCYR, PHDCSQ, APVNDR, APINV)
    );
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Int_factComprasEncabezados_PeriodoOrigen'
               AND object_id = OBJECT_ID('[int].factComprasEncabezados'))
    CREATE INDEX IX_Int_factComprasEncabezados_PeriodoOrigen ON [int].factComprasEncabezados (PeriodoOrigen)
        INCLUDE (EsVigente, Repeticiones, HuellaOrigen);
GO

-- stg ----------------------------------------------------------------------------------
IF OBJECT_ID('stg.factComprasEncabezados_Periodos') IS NULL
    CREATE TABLE stg.factComprasEncabezados_Periodos (
        Periodo  DECIMAL(8,0) NOT NULL CONSTRAINT PK_stg_factComprasEncabezados_Periodos PRIMARY KEY,
        RunId    INT          NULL
    );
GO
IF OBJECT_ID('stg.factComprasLineas_Periodos') IS NULL
    CREATE TABLE stg.factComprasLineas_Periodos (
        Periodo  DECIMAL(8,0) NOT NULL CONSTRAINT PK_stg_factComprasLineas_Periodos PRIMARY KEY,
        RunId    INT          NULL
    );
GO
IF OBJECT_ID('stg.factComprasEncabezados') IS NOT NULL AND COL_LENGTH('stg.factComprasEncabezados', 'APVNDR') IS NULL
    ALTER TABLE stg.factComprasEncabezados ADD APVNDR DECIMAL(8,0) NULL;
GO
IF OBJECT_ID('stg.factComprasEncabezados') IS NOT NULL AND COL_LENGTH('stg.factComprasEncabezados', 'APINV') IS NULL
    ALTER TABLE stg.factComprasEncabezados ADD APINV NVARCHAR(10) NULL;
GO
IF OBJECT_ID('stg.factComprasEncabezados') IS NOT NULL AND COL_LENGTH('stg.factComprasEncabezados', 'HUELLA') IS NULL
    ALTER TABLE stg.factComprasEncabezados ADD HUELLA BIGINT NULL;
GO
IF OBJECT_ID('stg.factComprasLineas') IS NOT NULL AND COL_LENGTH('stg.factComprasLineas', 'HUELLA') IS NULL
    ALTER TABLE stg.factComprasLineas ADD HUELLA BIGINT NULL;
GO

-- dw.factCompras -----------------------------------------------------------------------
IF COL_LENGTH('dw.factCompras', 'EsVigente') IS NULL
    ALTER TABLE dw.factCompras ADD EsVigente BIT NOT NULL
        CONSTRAINT DF_dw_factCompras_EsVigente DEFAULT (1);
GO
IF EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'UQ_dw_factCompras_Linea'
           AND parent_object_id = OBJECT_ID('dw.factCompras'))
    ALTER TABLE dw.factCompras DROP CONSTRAINT UQ_dw_factCompras_Linea;
GO
IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'UQ_dw_factCompras_LineaOrigen'
               AND parent_object_id = OBJECT_ID('dw.factCompras'))
    ALTER TABLE dw.factCompras ADD CONSTRAINT UQ_dw_factCompras_LineaOrigen
        UNIQUE (CodigoEmpresa, PrefijoDocumento, AnioDocumento, NumeroSecuenciaDocumento, NumeroLinea,
                CodigoProveedor, NumeroFacturaReferencia, FechaCreacion);
GO

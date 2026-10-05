-- 253: factVentas pasa a carga incremental por huella (ver db/etl/huella_as400.py y las 246-250 de
-- envios y compras). Estructura; los procedimientos van en la 254 (silver) y la 255 (gold).
--
-- Discovery del 2026-10-05 (SIH/SIL contra [int] en PROD):
--   * El AS400 PURGA las ventas: solo conserva desde 2026-06-03 (~4 meses, dias completos por
--     ILDATE). [int] es la unica copia de mayo y del 1-2 de junio (351.690 lineas).
--   * Compania+prefijo+documento+anio+tipo+linea se repite en 9 casos: son facturas distintas que
--     reusan el numero (ej. EX 40145 del 17/06 y del 19/06, con otros productos). Con la fecha de
--     factura (ILDATE) la llave es unica; sin ella [int] guardaba una sola factura de cada par.
--   * El encabezado (SIH) es unico por compania+documento+fecha de factura (SIINVD) y SIINVD = ILDATE
--     en el 100% de las lineas; el silver anterior cruzaba sin compania ni fecha y a esas 9 facturas
--     les ponia el encabezado de la otra.
--   * No se observaron encabezados que cambien despues de cargados: una sola huella por linea que
--     incluye las columnas del encabezado (JOIN en el AS400) detecta cambios de los dos.
--
-- [int].factVentas:
--   * Llave = compania + prefijo + documento + anio + tipo + linea + fecha de factura
--     (PeriodoOrigen = ILDATE del AS400 sin convertir). Indice unico agrupado (reemplaza la PK).
--   * PeriodoOrigen, Repeticiones y HuellaOrigen. EsVigente ya existia (siempre 1 hasta ahora).
-- stg.factVentas_Periodos: dias que el ultimo extract trajo completos (silver solo da de baja en
--   ellos, y nunca en dias anteriores al horizonte de purga; ver la 254).
-- stg.factVentasLineas: HUELLA; stg.factVentasEncabezados: SICOMP y SIINVD (para el cruce exacto).
--   Los extracts los auto-provisionan; se agregan aqui para que los procedimientos compilen.
-- dw.factVentas: la llave unica suma FechaUltimaTransaccion (= ILDATE).
-- Las filas existentes quedan con HuellaOrigen NULL: la primera corrida completa no cuadra ningun
-- dia y vuelve a traer una vez lo que tiene el AS400. Idempotente. Compatible con SQL Server 2016.

-- [int].factVentas -------------------------------------------------------------------------
IF COL_LENGTH('[int].factVentas', 'PeriodoOrigen') IS NULL
    ALTER TABLE [int].factVentas ADD PeriodoOrigen DECIMAL(8,0) NULL;
GO
IF COL_LENGTH('[int].factVentas', 'Repeticiones') IS NULL
    ALTER TABLE [int].factVentas ADD Repeticiones INT NOT NULL
        CONSTRAINT DF_Int_factVentas_Repeticiones DEFAULT (1);
GO
IF COL_LENGTH('[int].factVentas', 'HuellaOrigen') IS NULL
    ALTER TABLE [int].factVentas ADD HuellaOrigen DECIMAL(30,0) NULL;
GO

UPDATE [int].factVentas
SET PeriodoOrigen = CONVERT(DECIMAL(8,0), CONVERT(CHAR(8), ILDATE, 112))
WHERE PeriodoOrigen IS NULL AND ILDATE IS NOT NULL;
GO

IF EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'PK_Int_factVentas'
           AND parent_object_id = OBJECT_ID('[int].factVentas'))
    ALTER TABLE [int].factVentas DROP CONSTRAINT PK_Int_factVentas;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_Int_factVentas_Llave'
               AND object_id = OBJECT_ID('[int].factVentas'))
    CREATE UNIQUE CLUSTERED INDEX UX_Int_factVentas_Llave
        ON [int].factVentas (ILCOMP, ILDPFX, ILDOCN, ILDYR, ILDTYP, ILLINE, PeriodoOrigen);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Int_factVentas_PeriodoOrigen'
               AND object_id = OBJECT_ID('[int].factVentas'))
    CREATE INDEX IX_Int_factVentas_PeriodoOrigen ON [int].factVentas (PeriodoOrigen)
        INCLUDE (EsVigente, Repeticiones, HuellaOrigen);
GO

-- stg ----------------------------------------------------------------------------------------
IF OBJECT_ID('stg.factVentas_Periodos') IS NULL
    CREATE TABLE stg.factVentas_Periodos (
        Periodo  DECIMAL(8,0) NOT NULL CONSTRAINT PK_stg_factVentas_Periodos PRIMARY KEY,
        RunId    INT          NULL
    );
GO
IF OBJECT_ID('stg.factVentasLineas') IS NOT NULL AND COL_LENGTH('stg.factVentasLineas', 'HUELLA') IS NULL
    ALTER TABLE stg.factVentasLineas ADD HUELLA BIGINT NULL;
GO
IF OBJECT_ID('stg.factVentasEncabezados') IS NOT NULL AND COL_LENGTH('stg.factVentasEncabezados', 'SICOMP') IS NULL
    ALTER TABLE stg.factVentasEncabezados ADD SICOMP DECIMAL(2,0) NULL;
GO
IF OBJECT_ID('stg.factVentasEncabezados') IS NOT NULL AND COL_LENGTH('stg.factVentasEncabezados', 'SIINVD') IS NULL
    ALTER TABLE stg.factVentasEncabezados ADD SIINVD DECIMAL(8,0) NULL;
GO

-- dw.factVentas --------------------------------------------------------------------------------
IF EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'UQ_dw_factVentas_Linea'
           AND parent_object_id = OBJECT_ID('dw.factVentas'))
    ALTER TABLE dw.factVentas DROP CONSTRAINT UQ_dw_factVentas_Linea;
GO
IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'UQ_dw_factVentas_LineaOrigen'
               AND parent_object_id = OBJECT_ID('dw.factVentas'))
    ALTER TABLE dw.factVentas ADD CONSTRAINT UQ_dw_factVentas_LineaOrigen
        UNIQUE (CodigoEmpresa, PrefijoDocumento, NumeroDocumento, AnioDocumento, TipoDocumento, NumeroLinea,
                FechaUltimaTransaccion);
GO

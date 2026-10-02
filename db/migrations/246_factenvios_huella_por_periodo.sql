-- 246: factEnvios deja de ser FULL: carga incremental por huella (ver db/etl/huella_as400.py).
-- El extract compara por dia (ENCFEC tal cual viene del AS400) la cantidad de filas y la suma
-- de huellas del AS400 contra [int], y solo trae los dias que no cuadran.
--
-- Columnas nuevas en [int].factEnvios:
--   PeriodoOrigen  ENCFEC del AS400 sin convertir (DECIMAL AAAAMMDD). Se guarda aparte porque
--                  ENCFEC en [int] es DATE y las fechas invalidas del origen quedan NULL (6 filas);
--                  sin el valor original esos dias nunca cuadrarian.
--   Repeticiones   filas del AS400 con ese ENCENV (1 salvo el duplicado 550930 del 2024-10-23,
--                  doble pesaje el mismo dia); la cantidad por dia se compara con SUM(Repeticiones).
--   HuellaOrigen   suma de las huellas de esas filas (DECIMAL para que dos huellas no desborden).
-- Las filas que ya estaban quedan con HuellaOrigen NULL: la primera corrida despues de esta
-- migracion no cuadra ningun dia y vuelve a traer todo una vez (~213 k filas).
--
-- stg.factEnvios_Periodos: los dias que el ultimo extract trajo completos. Silver solo da de
-- baja (EsVigente = 0) envios de esos dias que ya no estan en el AS400.
-- Idempotente. Compatible con SQL Server 2016.

IF COL_LENGTH('[int].factEnvios', 'PeriodoOrigen') IS NULL
    ALTER TABLE [int].factEnvios ADD PeriodoOrigen DECIMAL(8,0) NULL;
GO

IF COL_LENGTH('[int].factEnvios', 'Repeticiones') IS NULL
    ALTER TABLE [int].factEnvios ADD Repeticiones INT NOT NULL
        CONSTRAINT DF_Int_factEnvios_Repeticiones DEFAULT (1);
GO

IF COL_LENGTH('[int].factEnvios', 'HuellaOrigen') IS NULL
    ALTER TABLE [int].factEnvios ADD HuellaOrigen DECIMAL(30,0) NULL;
GO

UPDATE [int].factEnvios
SET PeriodoOrigen = CONVERT(DECIMAL(8,0), CONVERT(CHAR(8), ENCFEC, 112))
WHERE PeriodoOrigen IS NULL AND ENCFEC IS NOT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Int_factEnvios_PeriodoOrigen'
               AND object_id = OBJECT_ID('[int].factEnvios'))
    CREATE INDEX IX_Int_factEnvios_PeriodoOrigen ON [int].factEnvios (PeriodoOrigen)
        INCLUDE (EsVigente, Repeticiones, HuellaOrigen);
GO

IF OBJECT_ID('stg.factEnvios_Periodos') IS NULL
    CREATE TABLE stg.factEnvios_Periodos (
        Periodo  DECIMAL(8,0) NOT NULL CONSTRAINT PK_stg_factEnvios_Periodos PRIMARY KEY,
        RunId    INT          NULL
    );
GO

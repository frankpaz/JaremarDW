-- 100: [int].factEnvios -- version Silver de stg.factEnvios.
-- Llave de negocio ENCENV (confirmado con el usuario: numero de envio,
-- practicamente unico en el origen -- 211290 distintos de 211292 filas,
-- 2 duplicados legitimos de doble pesaje mismo dia). No hay columna
-- confiable de fecha/hora de ultima modificacion en el origen (ENCFEU/
-- ENCTIU existen pero nunca se pueblan, confirmado: 0 filas con valor
-- distinto de 0 en 211292) -- se usa patron FULL + SCD Tipo 1 (igual que
-- factMeteoDaily), no watermark real: cada corrida trae la tabla completa y
-- el merge detecta altas/cambios via HashDiff, dejando una unica fila
-- vigente por ENCENV (estado actual, sin historial de versiones -- decision
-- explicita del usuario).
-- Se preservan los nombres de columna originales del AS400 (igual que
-- dimSector/dimEmpresas); el renombre a nombre de negocio ocurre solo en
-- dw (ver diccionario de campos confirmado por el usuario, 2026-09-22).
-- ENCFEC/ENCFEU (DECIMAL YYYYMMDD) -> DATE. ENCTIM/ENCTIU (DECIMAL
-- HHMMSSHH, centesimas de segundo) -> TIME(0).

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'factEnvios'
)
BEGIN
    CREATE TABLE [int].factEnvios (
        ENCENV          DECIMAL(8,0)  NOT NULL CONSTRAINT PK_Int_factEnvios PRIMARY KEY,
        ENCUSU          NVARCHAR(10)  NULL,
        ENCDSP          NVARCHAR(10)  NULL,
        ENCFEC          DATE          NULL,
        ENCTIM          TIME(0)       NULL,
        ENCCAM          NVARCHAR(6)   NULL,
        ENCPEC          DECIMAL(15,3) NULL,
        ENCCAD          NVARCHAR(30)  NULL,
        ENCEMT          DECIMAL(5,0)  NULL,
        ENCEMN          NVARCHAR(30)  NULL,
        ENCEN1          DECIMAL(5,0)  NULL,
        ENCED1          NVARCHAR(30)  NULL,
        ENCEN2          DECIMAL(5,0)  NULL,
        ENCED2          NVARCHAR(30)  NULL,
        ENCEN3          DECIMAL(5,0)  NULL,
        ENCED3          NVARCHAR(30)  NULL,
        ENCEN4          DECIMAL(5,0)  NULL,
        ENCED4          NVARCHAR(30)  NULL,
        ENCROU          NVARCHAR(6)   NULL,
        ENCDER          NVARCHAR(30)  NULL,
        ENCFEU          DATE          NULL,
        ENCTIU          TIME(0)       NULL,
        ENCSTA          NVARCHAR(1)   NULL,
        ENCPES          DECIMAL(9,3)  NULL,
        ENCPLA          NVARCHAR(10)  NULL,
        ENCDT1          NVARCHAR(30)  NULL,
        ENCPT2          NVARCHAR(30)  NULL,
        EsVigente       BIT           NOT NULL CONSTRAINT DF_Int_factEnvios_EsVigente DEFAULT (1),
        HashDiff        BINARY(32)    NOT NULL,
        FechaCargaInt   DATETIME2(7)  NOT NULL CONSTRAINT DF_Int_factEnvios_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId           INT           NULL
    );
END
GO

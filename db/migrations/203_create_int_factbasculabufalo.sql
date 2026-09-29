-- 203: [int].factBasculaBufalo -- version Silver de stg.factBasculaBufalo (PROLXUSRF.BASMASTNN, boletas de
-- bascula de las 4 basculas: 1 UNIMER KM 15, 2 OLEPSA KM 13, 3 BASCULA 3, 4 BUFINSA KM 13).
--
-- El origen no tiene llave unica ni fecha de modificacion. La llave la construimos nosotros:
-- BASCIA + NUMBOLET + FECHAGEN + HORAGEN (discovery 2026-09-29): unica en las 90.559 filas no
-- identicas, y en dos respaldos del AS400 tomados con ~10 meses de diferencia (BASMASTNBK vs
-- BASMASTBKN, 294.864 boletas) ninguna cambio de fecha/hora de generacion ni desaparecio.
-- NUMBOLET solo no sirve: se repite entre basculas y 12 veces dentro de la misma bascula.
-- Las filas identicas del origen (2 pares al 2026-09-29) se guardan una vez con Repeticiones.
--
-- Carga incremental por MERGE (ver 204): nunca se borra; lo que desaparece del AS400 queda con
-- EsVigente = 0. HORAGEN se guarda tal cual (entero HHMM, 3 boletas en HHMMSS) porque es parte
-- de la llave; su conversion a TIME se hace en gold.
-- No se cargan la pesada 4 (vacia), IMPRESO (siempre 'S') ni FECHAIN/FECHAOUT (texto sin ceros
-- a la izquierda, ambiguo; las fechas/horas de tara y bruto ya vienen limpias).
-- Compatible con SQL Server 2016.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'factBasculaBufalo'
)
BEGIN
    CREATE TABLE [int].factBasculaBufalo (
        [BASCIA]     INT            NOT NULL,
        [NUMBOLET]   INT            NOT NULL,
        [FECHAGEN]   DATE           NOT NULL,
        [HORAGEN]    INT            NOT NULL,
        [BASCUSER]   INT            NULL,
        [NUMENVIO]   INT            NULL,
        [BOLETY]     INT            NULL,
        [NUMPLACA]   NVARCHAR(10)   NULL,
        [MOTORITA]   NVARCHAR(40)   NULL,
        [ORIGEN]     INT            NULL,
        [NUMLUGAR]   INT            NULL,
        [PESOGEMAN]  DECIMAL(15,0)  NULL,
        [PESOTARA]   DECIMAL(15,0)  NULL,
        [FECHATAR]   DATE           NULL,
        [HORATARA]   TIME(0)        NULL,
        [PESOBRUT]   DECIMAL(15,0)  NULL,
        [FECHBRUT]   DATE           NULL,
        [HORABRUT]   TIME(0)        NULL,
        [PESONETO]   DECIMAL(15,0)  NULL,
        [DIFPESO]    DECIMAL(15,0)  NULL,
        [RIMPRESO]   NVARCHAR(1)    NULL,
        [ESTATUS]    NVARCHAR(1)    NULL,
        [NUMPROD]    INT            NULL,
        [NUMPROV]    INT            NULL,
        [MARCHAMO]   NVARCHAR(60)   NULL,
        [OBSERBA]    NVARCHAR(60)   NULL,
        [NUMDOCTS]   NVARCHAR(60)   NULL,
        [PESOAUDI]   DECIMAL(15,0)  NULL,
        [BASAUDIT]   NVARCHAR(30)   NULL,
        [MONTAR1]    NVARCHAR(35)   NULL,
        [MONTAR2]    NVARCHAR(35)   NULL,
        [MONTAR3]    NVARCHAR(35)   NULL,
        [MOMBRU1]    NVARCHAR(35)   NULL,
        [MOMBRU2]    NVARCHAR(35)   NULL,
        [MOMBRU3]    NVARCHAR(35)   NULL,
        [FECHATAR1]  DATE           NULL,
        [HORATARA1]  TIME(0)        NULL,
        [PESOTARA1]  DECIMAL(15,0)  NULL,
        [FECHATAR2]  DATE           NULL,
        [HORATARA2]  TIME(0)        NULL,
        [PESOTARA2]  DECIMAL(15,0)  NULL,
        [FECHATAR3]  DATE           NULL,
        [HORATARA3]  TIME(0)        NULL,
        [PESOTARA3]  DECIMAL(15,0)  NULL,
        [FECHBRUT1]  DATE           NULL,
        [HORABRUT1]  TIME(0)        NULL,
        [PESOBRUT1]  DECIMAL(15,0)  NULL,
        [FECHBRUT2]  DATE           NULL,
        [HORABRUT2]  TIME(0)        NULL,
        [PESOBRUT2]  DECIMAL(15,0)  NULL,
        [FECHBRUT3]  DATE           NULL,
        [HORABRUT3]  TIME(0)        NULL,
        [PESOBRUT3]  DECIMAL(15,0)  NULL,
        [PESOGEMAN1] DECIMAL(15,0)  NULL,
        [PESOGEMAN2] DECIMAL(15,0)  NULL,
        [PESOGEMAN3] DECIMAL(15,0)  NULL,
        [PESONETO1]  DECIMAL(15,0)  NULL,
        [PESONETO2]  DECIMAL(15,0)  NULL,
        [PESONETO3]  DECIMAL(15,0)  NULL,
        [DIFPESO1]   DECIMAL(15,0)  NULL,
        [DIFPESO2]   DECIMAL(15,0)  NULL,
        [DIFPESO3]   DECIMAL(15,0)  NULL,
        [MARCACAM]   NVARCHAR(30)   NULL,
        [COLORCAM]   NVARCHAR(30)   NULL,
        [NUMDOCTO]   NVARCHAR(10)   NULL,
        [FECDCTOO]   DATE           NULL,
        [STATUS1]    NVARCHAR(1)    NULL,
        [STATUS2]    NVARCHAR(1)    NULL,
        [ENCARGADO]  NVARCHAR(40)   NULL,
        [ONLINE]     NVARCHAR(30)   NULL,
        [IDENTIN]    NVARCHAR(15)   NULL,
        [IDENTOUT]   NVARCHAR(15)   NULL,
        Repeticiones INT            NOT NULL CONSTRAINT DF_Int_factBasculaBufalo_Repeticiones DEFAULT (1),
        EsVigente    BIT            NOT NULL CONSTRAINT DF_Int_factBasculaBufalo_EsVigente DEFAULT (1),
        HashDiff     BINARY(32)     NOT NULL,
        FechaAlta    DATETIME2(7)   NOT NULL CONSTRAINT DF_Int_factBasculaBufalo_FechaAlta DEFAULT (SYSDATETIME()),
        FechaUltimoCambio DATETIME2(7)   NULL,
        FechaCargaInt DATETIME2(7)   NOT NULL CONSTRAINT DF_Int_factBasculaBufalo_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId        INT            NULL,
        CONSTRAINT PK_Int_factBasculaBufalo PRIMARY KEY (BASCIA, NUMBOLET, FECHAGEN, HORAGEN)
    );
    CREATE INDEX IX_Int_factBasculaBufalo_FechaCargaInt ON [int].factBasculaBufalo (FechaCargaInt);
    CREATE INDEX IX_Int_factBasculaBufalo_FechaGen ON [int].factBasculaBufalo (FECHAGEN) INCLUDE (ESTATUS, EsVigente);
END
GO

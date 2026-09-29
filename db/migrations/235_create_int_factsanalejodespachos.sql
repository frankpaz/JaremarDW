-- 235: [int].factSanAlejoDespachos -- version Silver de stg.factSanAlejoDespachos (PIDSA.SPVHST01, "Historico de Transacciones Diarias de O.P. (otros productos)").
-- Dominio SanAlejo: despachos (salidas) de otros productos de las extractoras -- aceite crudo, oleinas, estearinas,
-- RBD, harina, almendra, fibra... -- a clientes y entre empresas: una fila por boleta de bascula.
--
-- Llave de negocio CODCIA + NUMDOC (empresa + numero de documento): unica en todo lo cargado
-- (historico acordado desde 2025-01-01; discovery 2026-09-29). Si el origen repitiera una llave, se
-- guarda una vez y Repeticiones cuenta cuantas eran. Carga incremental por MERGE (ver 236): nunca
-- se borra; lo que desaparece del AS400 queda con EsVigente = 0.
-- No se cargan las columnas vacias desde 2025 ni DIA/MES/AÑO (repiten FECDOC). Fechas AAAAMMDD a DATE
-- (invalidas -> NULL, ej. 21171310) y horas HHMMSS a TIME(0).
-- Compatible con SQL Server 2016.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'factSanAlejoDespachos'
)
BEGIN
    CREATE TABLE [int].factSanAlejoDespachos (
        [CODCIA]    INT            NOT NULL,
        [NUMDOC]    BIGINT         NOT NULL,
        [CODSUC]    INT            NULL,
        [NUMID]     BIGINT         NULL,
        [FECDOC]    DATE           NULL,
        [HORDOC]    TIME(0)        NULL,
        [PLACA]     NVARCHAR(9)    NULL,
        [CODCLI]    INT            NULL,
        [NOMBRE]    NVARCHAR(30)   NULL,
        [CONDUC]    NVARCHAR(30)   NULL,
        [TIPOP]     NVARCHAR(5)    NULL,
        [BRUTO]     DECIMAL(7,0)   NULL,
        [TARA]      DECIMAL(7,0)   NULL,
        [NETO]      DECIMAL(7,0)   NULL,
        [CODTRA]    INT            NULL,
        [CODLOC]    INT            NULL,
        [SELLO1]    NVARCHAR(10)   NULL,
        [SELLO2]    NVARCHAR(10)   NULL,
        [SELLO3]    NVARCHAR(10)   NULL,
        [SELLO4]    NVARCHAR(10)   NULL,
        [SELLO5]    NVARCHAR(10)   NULL,
        [SELLO6]    NVARCHAR(10)   NULL,
        [SELLO7]    NVARCHAR(10)   NULL,
        [SELLO8]    NVARCHAR(10)   NULL,
        [SELLO9]    NVARCHAR(10)   NULL,
        [COMEN1]    NVARCHAR(50)   NULL,
        [COMEN2]    NVARCHAR(50)   NULL,
        [COMEN3]    NVARCHAR(50)   NULL,
        [USUARI]    NVARCHAR(10)   NULL,
        [PORACI]    DECIMAL(5,3)   NULL,
        [PORHUM]    DECIMAL(5,3)   NULL,
        [MARMOD]    NVARCHAR(1)    NULL,
        [USUMOD]    NVARCHAR(10)   NULL,
        [FECMOD]    DATE           NULL,
        [NUMTIK]    NVARCHAR(10)   NULL,
        [FECSAL]    DATE           NULL,
        [HORSAL]    TIME(0)        NULL,
        [NOPEDI]    BIGINT         NULL,
        [FEPEDI]    DATE           NULL,
        [NUMFAC]    BIGINT         NULL,
        [FECFAC]    DATE           NULL,
        [CERTIF]    NVARCHAR(2)    NULL,
        [MODEL]     NVARCHAR(5)    NULL,
        [RSPCOR]    DECIMAL(20,0)  NULL,
        [PROSUS]    NVARCHAR(2)    NULL,
        [BOLVEN]    DECIMAL(20,0)  NULL,
        [SEMAN]     INT            NULL,
        [PEROPR]    INT            NULL,
        [MESC]      INT            NULL,
        [AÑOC]      INT            NULL,
        [P1NPLA]    NVARCHAR(10)   NULL,
        [P2NPLAC]   NVARCHAR(10)   NULL,
        [M1IDM]     NVARCHAR(20)   NULL,
        [T1CTRA]    NVARCHAR(10)   NULL,
        [CARAC1]    NVARCHAR(20)   NULL,
        [CARAC2]    NVARCHAR(20)   NULL,
        [CARAC3]    NVARCHAR(20)   NULL,
        [CARAC4]    NVARCHAR(20)   NULL,
        [CARAC5]    NVARCHAR(20)   NULL,
        [CARAC6]    NVARCHAR(20)   NULL,
        [CARAC7]    NVARCHAR(20)   NULL,
        [DIGIT1]    DECIMAL(15,2)  NULL,
        [DIGIT2]    DECIMAL(15,2)  NULL,
        [DIGIT6]    DECIMAL(15,0)  NULL,
        [DIGIT7]    DECIMAL(15,0)  NULL,
        [HORAB]     TIME(0)        NULL,
        [HORAT]     TIME(0)        NULL,
        [FECHAT]    DATE           NULL,
        [FECHAB]    DATE           NULL,
        [IDING]     BIGINT         NULL,
        [IDSAL]     BIGINT         NULL,
        [REFDOC]    BIGINT         NULL,
        [REFPES]    DECIMAL(7,0)   NULL,
        [FECENV]    DATE           NULL,
        [NUMENV]    BIGINT         NULL,
        Repeticiones INT            NOT NULL CONSTRAINT DF_Int_factSanAlejoDespachos_Repeticiones DEFAULT (1),
        EsVigente   BIT            NOT NULL CONSTRAINT DF_Int_factSanAlejoDespachos_EsVigente DEFAULT (1),
        HashDiff    BINARY(32)     NOT NULL,
        FechaAlta   DATETIME2(7)   NOT NULL CONSTRAINT DF_Int_factSanAlejoDespachos_FechaAlta DEFAULT (SYSDATETIME()),
        FechaUltimoCambio DATETIME2(7)   NULL,
        FechaCargaInt DATETIME2(7)   NOT NULL CONSTRAINT DF_Int_factSanAlejoDespachos_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId       INT            NULL,
        CONSTRAINT PK_Int_factSanAlejoDespachos PRIMARY KEY (CODCIA, NUMDOC)
    );
    CREATE INDEX IX_Int_factSanAlejoDespachos_FechaCargaInt ON [int].factSanAlejoDespachos (FechaCargaInt);
    CREATE INDEX IX_Int_factSanAlejoDespachos_FechaDoc ON [int].factSanAlejoDespachos (FECDOC) INCLUDE (EsVigente);
END
GO

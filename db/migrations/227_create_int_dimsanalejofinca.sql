-- 227: [int].dimSanAlejoFinca -- version Silver de stg.dimSanAlejoFinca (PIDSA.SPVTAB00, fincas por empresa).
-- Dominio SanAlejo. Llave de negocio CODCIA + FINCA.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'dimSanAlejoFinca'
)
BEGIN
    CREATE TABLE [int].dimSanAlejoFinca (
        [CODCIA]   INT            NOT NULL,
        [FINCA]    NVARCHAR(5)    NOT NULL,
        [CODSUC]   INT            NULL,
        [FRENTE]   NVARCHAR(50)   NULL,
        [EXTEN]    DECIMAL(10,3)  NULL,
        [DESFIN]   NVARCHAR(100)  NULL,
        [VARIED]   NVARCHAR(50)   NULL,
        [PREFFB]   DECIMAL(13,2)  NULL,
        [NOPLA]    NVARCHAR(4)    NULL,
        [CIAREL]   INT            NULL,
        [STATUS]   NVARCHAR(1)    NULL,
        EsVigente  BIT            NOT NULL CONSTRAINT DF_Int_dimSanAlejoFinca_EsVigente DEFAULT (1),
        HashDiff   BINARY(32)     NOT NULL,
        FechaCargaInt DATETIME2(7)   NOT NULL CONSTRAINT DF_Int_dimSanAlejoFinca_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId      INT            NULL,
        CONSTRAINT PK_Int_dimSanAlejoFinca PRIMARY KEY (CODCIA, FINCA)
    );
END
GO

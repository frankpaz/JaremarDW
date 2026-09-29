-- 223: [int].dimSanAlejoProductor -- version Silver de stg.dimSanAlejoProductor (PIDSA.PIMST00, maestro de productores independientes de fruta).
-- Dominio SanAlejo. Llave de negocio CODCIA + CODPRO.
-- No se cargan representante legal, direccion, RTN, identidad, telefono, banco ni cuenta bancaria
-- (datos personales), ni los comentarios y campos libres.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'dimSanAlejoProductor'
)
BEGIN
    CREATE TABLE [int].dimSanAlejoProductor (
        [CODCIA]   INT            NOT NULL,
        [CODPRO]   INT            NOT NULL,
        [NOMPRO]   NVARCHAR(80)   NULL,
        [UBICA]    NVARCHAR(150)  NULL,
        [SECTOR]   NVARCHAR(4)    NULL,
        [ESTADO]   INT            NULL,
        [TOTHEC]   DECIMAL(10,3)  NULL,
        [NUMCON]   BIGINT         NULL,
        [FECCON]   DATE           NULL,
        [FECFIN]   DATE           NULL,
        [CODLOC]   INT            NULL,
        [CODANT]   INT            NULL,
        EsVigente  BIT            NOT NULL CONSTRAINT DF_Int_dimSanAlejoProductor_EsVigente DEFAULT (1),
        HashDiff   BINARY(32)     NOT NULL,
        FechaCargaInt DATETIME2(7)   NOT NULL CONSTRAINT DF_Int_dimSanAlejoProductor_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId      INT            NULL,
        CONSTRAINT PK_Int_dimSanAlejoProductor PRIMARY KEY (CODCIA, CODPRO)
    );
END
GO

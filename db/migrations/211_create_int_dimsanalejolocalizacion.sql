-- 211: [int].dimSanAlejoLocalizacion -- version Silver de stg.dimSanAlejoLocalizacion (PIDSA.SPVTAB06, localizaciones (origen/destino) por empresa).
-- Dominio SanAlejo. Llave de negocio CODCIA + CODLOC.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'dimSanAlejoLocalizacion'
)
BEGIN
    CREATE TABLE [int].dimSanAlejoLocalizacion (
        [CODCIA]   INT            NOT NULL,
        [CODLOC]   INT            NOT NULL,
        [ORIGEN]   NVARCHAR(80)   NULL,
        [DESTIN]   NVARCHAR(80)   NULL,
        [PRECTM]   DECIMAL(13,4)  NULL,
        [COSTOK]   DECIMAL(13,4)  NULL,
        [CODTAR]   NVARCHAR(30)   NULL,
        [SECTOR]   NVARCHAR(4)    NULL,
        [CAMPO1]   NVARCHAR(30)   NULL,
        [MARCA]    NVARCHAR(1)    NULL,
        EsVigente  BIT            NOT NULL CONSTRAINT DF_Int_dimSanAlejoLocalizacion_EsVigente DEFAULT (1),
        HashDiff   BINARY(32)     NOT NULL,
        FechaCargaInt DATETIME2(7)   NOT NULL CONSTRAINT DF_Int_dimSanAlejoLocalizacion_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId      INT            NULL,
        CONSTRAINT PK_Int_dimSanAlejoLocalizacion PRIMARY KEY (CODCIA, CODLOC)
    );
END
GO

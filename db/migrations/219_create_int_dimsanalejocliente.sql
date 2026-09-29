-- 219: [int].dimSanAlejoCliente -- version Silver de stg.dimSanAlejoCliente (PIDSA.SPVTAB11, clientes de la bascula por empresa).
-- Dominio SanAlejo. Llave de negocio CODCIA + CODCLI.
-- No se cargan telefono, fax, correo ni RTN. Es el catalogo propio de la bascula: solo ~37 % de
-- los clientes de despachos existen en dw.dimCliente (ERP); 999994-999998 son genericos.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'dimSanAlejoCliente'
)
BEGIN
    CREATE TABLE [int].dimSanAlejoCliente (
        [CODCIA]   INT            NOT NULL,
        [CODCLI]   INT            NOT NULL,
        [NOMCLI]   NVARCHAR(80)   NULL,
        [DIRCLI]   NVARCHAR(80)   NULL,
        EsVigente  BIT            NOT NULL CONSTRAINT DF_Int_dimSanAlejoCliente_EsVigente DEFAULT (1),
        HashDiff   BINARY(32)     NOT NULL,
        FechaCargaInt DATETIME2(7)   NOT NULL CONSTRAINT DF_Int_dimSanAlejoCliente_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId      INT            NULL,
        CONSTRAINT PK_Int_dimSanAlejoCliente PRIMARY KEY (CODCIA, CODCLI)
    );
END
GO

-- 207: [int].dimSanAlejoProducto -- version Silver de stg.dimSanAlejoProducto (PIDSA.SPVTAB08, productos de la bascula de las extractoras).
-- Dominio SanAlejo. Llave de negocio COPROD.
-- CODALT es el codigo del producto en el ERP (cruza con dw.dimProducto en 36 de los 40 que lo traen).

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'dimSanAlejoProducto'
)
BEGIN
    CREATE TABLE [int].dimSanAlejoProducto (
        [COPROD]   NVARCHAR(5)    NOT NULL,
        [NOPROD]   NVARCHAR(100)  NULL,
        [CODALT]   NVARCHAR(35)   NULL,
        [UNIMED]   NVARCHAR(3)    NULL,
        [PREPRO]   DECIMAL(15,4)  NULL,
        [CERTIF]   NVARCHAR(20)   NULL,
        EsVigente  BIT            NOT NULL CONSTRAINT DF_Int_dimSanAlejoProducto_EsVigente DEFAULT (1),
        HashDiff   BINARY(32)     NOT NULL,
        FechaCargaInt DATETIME2(7)   NOT NULL CONSTRAINT DF_Int_dimSanAlejoProducto_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId      INT            NULL,
        CONSTRAINT PK_Int_dimSanAlejoProducto PRIMARY KEY (COPROD)
    );
END
GO

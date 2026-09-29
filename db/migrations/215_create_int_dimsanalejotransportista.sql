-- 215: [int].dimSanAlejoTransportista -- version Silver de stg.dimSanAlejoTransportista (PIDSA.SPVTAB05, transportistas por empresa).
-- Dominio SanAlejo. Llave de negocio CODCIA + CODTRA.
-- No se cargan direccion, telefonos, RTN, identidad, cuenta bancaria ni correos (datos personales).
-- 11 llaves vienen repetidas en el origen: queda una (la de nombre mayor). CODALX es el codigo
-- del proveedor en el ERP (cruza con dw.dimProveedor en 445 de 521).

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'dimSanAlejoTransportista'
)
BEGIN
    CREATE TABLE [int].dimSanAlejoTransportista (
        [CODCIA]   INT            NOT NULL,
        [CODTRA]   INT            NOT NULL,
        [NOMTRA]   NVARCHAR(70)   NULL,
        [VALKIL]   DECIMAL(12,4)  NULL,
        [PRECIO]   DECIMAL(12,2)  NULL,
        [CODALX]   INT            NULL,
        EsVigente  BIT            NOT NULL CONSTRAINT DF_Int_dimSanAlejoTransportista_EsVigente DEFAULT (1),
        HashDiff   BINARY(32)     NOT NULL,
        FechaCargaInt DATETIME2(7)   NOT NULL CONSTRAINT DF_Int_dimSanAlejoTransportista_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId      INT            NULL,
        CONSTRAINT PK_Int_dimSanAlejoTransportista PRIMARY KEY (CODCIA, CODTRA)
    );
END
GO

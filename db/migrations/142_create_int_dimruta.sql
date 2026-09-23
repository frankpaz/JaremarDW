-- 142: [int].dimRuta -- version Silver de stg.dimRuta (PROLX835F.ZCC,
-- CCTABL='ROUTE': catalogo de rutas, 514 filas). Llave de negocio CCCODE
-- (unica, sin duplicados). Se descartan por poblacion 0%: CCLANG, CCALTC,
-- CCSDSC, CCNOT2, CCUDC1-3, CCRESV y los indicadores de revision; CCNOT1
-- (1 de 514 filas) tambien se descarta por decision del usuario.
-- CCENDT/CCMNDT (yyyymmdd) -> DATE y CCENTM/CCMNTM (hhmmss) -> TIME(0); si la
-- fecha de origen es 0 la hora queda NULL.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'dimRuta'
)
BEGIN
    CREATE TABLE [int].dimRuta (
        CCCODE          NVARCHAR(15)  NOT NULL CONSTRAINT PK_Int_dimRuta PRIMARY KEY,
        CCDESC          NVARCHAR(30)  NULL,
        CCENDT          DATE          NULL,
        CCENTM          TIME(0)       NULL,
        CCENUS          NVARCHAR(10)  NULL,
        CCMNDT          DATE          NULL,
        CCMNTM          TIME(0)       NULL,
        CCMNUS          NVARCHAR(10)  NULL,
        EsVigente       BIT           NOT NULL CONSTRAINT DF_Int_dimRuta_EsVigente DEFAULT (1),
        HashDiff        BINARY(32)    NOT NULL,
        FechaCargaInt   DATETIME2(7)  NOT NULL CONSTRAINT DF_Int_dimRuta_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId           INT           NULL
    );
END
GO

-- 128: [int].dimPais -- version Silver de stg.dimPais.
-- Fuente: PROLX835F.LCN, CNID='CN' ("Country Master"). Llave de negocio
-- CNCNTY (codigo estilo ISO 3166-1 alpha-3, ej HND/GTM/SLV), 244 filas,
-- unica verificada. Patron FULL + SCD Tipo 1.
-- CNLDTE/CNCDTE (DECIMAL YYYYMMDD) -> DATE. CNLTME/CNCTME (DECIMAL HHMMSS)
-- -> TIME(0).
-- Se preservan los nombres de columna originales del AS400; el renombre a
-- nombre de negocio (y el enriquecimiento con alpha-2/numerico ISO) ocurre
-- solo en dw.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'dimPais'
)
BEGIN
    CREATE TABLE [int].dimPais (
        CNCNTY          NVARCHAR(3)   NOT NULL CONSTRAINT PK_Int_dimPais PRIMARY KEY,
        CNLDSC          NVARCHAR(30)  NULL,
        CNSDSC          NVARCHAR(15)  NULL,
        CNLANG          NVARCHAR(3)   NULL,
        CNLUSR          NVARCHAR(10)  NULL,
        CNLDTE          DATE          NULL,
        CNLTME          TIME(0)       NULL,
        CNCUSR          NVARCHAR(10)  NULL,
        CNCDTE          DATE          NULL,
        CNCTME          TIME(0)       NULL,
        EsVigente       BIT           NOT NULL CONSTRAINT DF_Int_dimPais_EsVigente DEFAULT (1),
        HashDiff        BINARY(32)    NOT NULL,
        FechaCargaInt   DATETIME2(7)  NOT NULL CONSTRAINT DF_Int_dimPais_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId           INT           NULL
    );
END
GO

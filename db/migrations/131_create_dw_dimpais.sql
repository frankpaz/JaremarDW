-- 131: dw.dimPais -- dimension Gold (SCD Tipo 1), a partir de [int].dimPais,
-- enriquecida con ref.PaisesIso3166 (alpha-2, numerico) via LEFT JOIN por
-- Alpha3 -- LCN (AS400) solo trae el codigo alpha-3.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'dimPais'
)
BEGIN
    CREATE TABLE dw.dimPais (
        PaisKey                     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_dimPais PRIMARY KEY,
        CodigoPaisAlpha3             NVARCHAR(3)   NOT NULL,
        CodigoPaisAlpha2             NVARCHAR(2)   NULL,
        CodigoPaisNumerico           NVARCHAR(3)   NULL,
        NombrePais                   NVARCHAR(30)  NULL,
        NombreCortoPais              NVARCHAR(15)  NULL,
        CodigoIdioma                 NVARCHAR(3)   NULL,
        FechaCreacion                DATE          NULL,
        HoraCreacion                 TIME(0)       NULL,
        UsuarioCreacion              NVARCHAR(10)  NULL,
        FechaUltimaModificacion      DATE          NULL,
        HoraUltimaModificacion       TIME(0)       NULL,
        UsuarioUltimaModificacion    NVARCHAR(10)  NULL,
        EsVigente                    BIT           NOT NULL CONSTRAINT DF_dw_dimPais_EsVigente DEFAULT (1),
        HashDiff                     BINARY(32)    NOT NULL,
        FechaCargaDw                 DATETIME2(7)  NOT NULL CONSTRAINT DF_dw_dimPais_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId                        INT           NULL,
        CONSTRAINT UQ_dw_dimPais_CodigoAlpha3 UNIQUE (CodigoPaisAlpha3)
    );
END
GO

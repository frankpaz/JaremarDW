-- 144: dw.dimRuta -- dimension Gold (SCD Tipo 1), a partir de [int].dimRuta.
-- Nombres de negocio (mismo criterio de FechaCreacion/HoraCreacion/
-- UsuarioCreacion que factVentas). Los hechos aun no la referencian: agregar
-- RutaKey a factVentas (SIROUT, 100% de cobertura) y factEnvios (ENCROU, ~69%
-- de las rutas distintas hacen match) es un paso posterior, con LEFT JOIN.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'dimRuta'
)
BEGIN
    CREATE TABLE dw.dimRuta (
        RutaKey              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_dimRuta PRIMARY KEY,
        CodigoRuta            NVARCHAR(15)  NOT NULL,
        NombreRuta            NVARCHAR(30)  NULL,
        FechaCreacion         DATE          NULL,
        HoraCreacion          TIME(0)       NULL,
        UsuarioCreacion       NVARCHAR(10)  NULL,
        FechaModificacion     DATE          NULL,
        HoraModificacion      TIME(0)       NULL,
        UsuarioModificacion   NVARCHAR(10)  NULL,
        EsVigente             BIT           NOT NULL CONSTRAINT DF_dw_dimRuta_EsVigente DEFAULT (1),
        HashDiff              BINARY(32)    NOT NULL,
        FechaCargaDw          DATETIME2(7)  NOT NULL CONSTRAINT DF_dw_dimRuta_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId                 INT           NULL,
        CONSTRAINT UQ_dw_dimRuta_CodigoRuta UNIQUE (CodigoRuta)
    );
END
GO

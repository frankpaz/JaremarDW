-- 021: dw.dimSector -- dimension Gold (SCD Tipo 1), a partir de [int].dimSector.
-- CodigoSector/DescripcionSector (patron de nombre igual a dimClasesProducto:
-- codigo + descripcion, no un nombre legal como dimEmpresas). FechaRegistro/
-- HoraRegistro son supuesto, sin confirmar. SVID sin renombrar (sin base
-- para asignarle un nombre de negocio, mismo caso que dimEmpresas).

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'dimSector'
)
BEGIN
    CREATE TABLE dw.dimSector (
        SectorKey            INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_dimSector PRIMARY KEY,
        CodigoSector           NVARCHAR(16)  NOT NULL,
        SVID                   NVARCHAR(2)   NULL,
        DescripcionSector      NVARCHAR(30)  NULL,
        FechaRegistro          DATE          NULL,
        HoraRegistro           TIME(0)       NULL,
        EsVigente              BIT           NOT NULL CONSTRAINT DF_dw_dimSector_EsVigente DEFAULT (1),
        HashDiff               BINARY(32)    NOT NULL,
        FechaCargaDw           DATETIME2(7)  NOT NULL CONSTRAINT DF_dw_dimSector_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId                  INT           NULL,
        CONSTRAINT UQ_dw_dimSector_CodigoSector UNIQUE (CodigoSector)
    );
END
GO

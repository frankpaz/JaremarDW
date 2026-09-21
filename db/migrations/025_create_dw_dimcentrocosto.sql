-- 025: dw.dimCentroCosto -- dimension Gold (SCD Tipo 1), a partir de [int].dimCentroCosto.
-- CodigoCentroCosto/DescripcionCentroCosto (patron codigo+descripcion, igual
-- que dimClasesProducto/dimSector). FechaRegistro/HoraRegistro son supuesto,
-- sin confirmar. SVID sin renombrar (mismo caso que dimEmpresas/dimSector).

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'dimCentroCosto'
)
BEGIN
    CREATE TABLE dw.dimCentroCosto (
        CentroCostoKey          INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_dimCentroCosto PRIMARY KEY,
        CodigoCentroCosto         NVARCHAR(16)  NOT NULL,
        SVID                      NVARCHAR(2)   NULL,
        DescripcionCentroCosto    NVARCHAR(30)  NULL,
        FechaRegistro             DATE          NULL,
        HoraRegistro              TIME(0)       NULL,
        EsVigente                 BIT           NOT NULL CONSTRAINT DF_dw_dimCentroCosto_EsVigente DEFAULT (1),
        HashDiff                  BINARY(32)    NOT NULL,
        FechaCargaDw              DATETIME2(7)  NOT NULL CONSTRAINT DF_dw_dimCentroCosto_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId                     INT           NULL,
        CONSTRAINT UQ_dw_dimCentroCosto_CodigoCentroCosto UNIQUE (CodigoCentroCosto)
    );
END
GO

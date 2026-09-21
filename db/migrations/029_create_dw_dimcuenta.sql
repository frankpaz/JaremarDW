-- 029: dw.dimCuenta -- dimension Gold (SCD Tipo 1), a partir de [int].dimCuenta.
-- CodigoCuenta/DescripcionCuenta (patron codigo+descripcion, igual que
-- dimSector/dimCentroCosto/dimClasesProducto). FechaRegistro/HoraRegistro
-- supuesto, sin confirmar. SVID sin renombrar.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'dimCuenta'
)
BEGIN
    CREATE TABLE dw.dimCuenta (
        CuentaKey          INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_dimCuenta PRIMARY KEY,
        CodigoCuenta         NVARCHAR(16)  NOT NULL,
        SVID                 NVARCHAR(2)   NULL,
        DescripcionCuenta    NVARCHAR(30)  NULL,
        FechaRegistro        DATE          NULL,
        HoraRegistro         TIME(0)       NULL,
        EsVigente            BIT           NOT NULL CONSTRAINT DF_dw_dimCuenta_EsVigente DEFAULT (1),
        HashDiff             BINARY(32)    NOT NULL,
        FechaCargaDw         DATETIME2(7)  NOT NULL CONSTRAINT DF_dw_dimCuenta_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId                INT           NULL,
        CONSTRAINT UQ_dw_dimCuenta_CodigoCuenta UNIQUE (CodigoCuenta)
    );
END
GO

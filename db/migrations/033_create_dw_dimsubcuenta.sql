-- 033: dw.dimSubCuenta -- dimension Gold (SCD Tipo 1), a partir de [int].dimSubCuenta.
-- CodigoSubCuenta/DescripcionSubCuenta (patron codigo+descripcion, igual que
-- dimCuenta/dimSector/dimCentroCosto). FechaRegistro/HoraRegistro supuesto,
-- sin confirmar. SVID sin renombrar.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'dimSubCuenta'
)
BEGIN
    CREATE TABLE dw.dimSubCuenta (
        SubCuentaKey          INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_dimSubCuenta PRIMARY KEY,
        CodigoSubCuenta         NVARCHAR(16)  NOT NULL,
        SVID                    NVARCHAR(2)   NULL,
        DescripcionSubCuenta    NVARCHAR(30)  NULL,
        FechaRegistro           DATE          NULL,
        HoraRegistro            TIME(0)       NULL,
        EsVigente               BIT           NOT NULL CONSTRAINT DF_dw_dimSubCuenta_EsVigente DEFAULT (1),
        HashDiff                BINARY(32)    NOT NULL,
        FechaCargaDw            DATETIME2(7)  NOT NULL CONSTRAINT DF_dw_dimSubCuenta_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId                   INT           NULL,
        CONSTRAINT UQ_dw_dimSubCuenta_CodigoSubCuenta UNIQUE (CodigoSubCuenta)
    );
END
GO

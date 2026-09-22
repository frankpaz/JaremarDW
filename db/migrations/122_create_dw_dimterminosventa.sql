-- 122: dw.dimTerminosVenta -- dimension Gold (SCD Tipo 1), a partir de
-- [int].dimTerminosVenta. Nombres de negocio segun diccionario de campos
-- real de RTM (2026-09-22).

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'dimTerminosVenta'
)
BEGIN
    CREATE TABLE dw.dimTerminosVenta (
        TerminoVentaKey             INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_dimTerminosVenta PRIMARY KEY,
        NumeroEmpresa                DECIMAL(2,0)  NOT NULL,
        CodigoTerminos               NVARCHAR(2)   NOT NULL,
        Descripcion                  NVARCHAR(15)  NULL,
        DiasVencimiento              DECIMAL(5,0)  NULL,
        ImpuestoAntesDescuento       NVARCHAR(1)   NULL,
        ImpuestoSobreNetoDescuento   NVARCHAR(1)   NULL,
        PagoContraOrden              NVARCHAR(1)   NULL,
        EsVigente                    BIT           NOT NULL CONSTRAINT DF_dw_dimTerminosVenta_EsVigente DEFAULT (1),
        HashDiff                     BINARY(32)    NOT NULL,
        FechaCargaDw                 DATETIME2(7)  NOT NULL CONSTRAINT DF_dw_dimTerminosVenta_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId                        INT           NULL,
        CONSTRAINT UQ_dw_dimTerminosVenta_Codigo UNIQUE (NumeroEmpresa, CodigoTerminos)
    );
END
GO

-- 126: dw.dimTerminosCompra -- dimension Gold (SCD Tipo 1), a partir de
-- [int].dimTerminosCompra. Nombres de negocio segun diccionario de campos
-- real de AVT (2026-09-22).

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'dimTerminosCompra'
)
BEGIN
    CREATE TABLE dw.dimTerminosCompra (
        TerminoCompraKey        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_dimTerminosCompra PRIMARY KEY,
        CodigoTerminos           NVARCHAR(2)   NOT NULL,
        Descripcion              NVARCHAR(15)  NULL,
        DiasVencimiento          DECIMAL(3,0)  NULL,
        ImpuestoAntesDescuento   NVARCHAR(1)   NULL,
        EsVigente                BIT           NOT NULL CONSTRAINT DF_dw_dimTerminosCompra_EsVigente DEFAULT (1),
        HashDiff                 BINARY(32)    NOT NULL,
        FechaCargaDw             DATETIME2(7)  NOT NULL CONSTRAINT DF_dw_dimTerminosCompra_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId                    INT           NULL,
        CONSTRAINT UQ_dw_dimTerminosCompra_Codigo UNIQUE (CodigoTerminos)
    );
END
GO
